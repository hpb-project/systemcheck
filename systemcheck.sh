#!/bin/bash 

if [ `id -u` -eq 0 ];
then
    echo "开始检查..."
else
    echo "请使用root权限执行脚本!"
    exit 1
fi

exec 2>/dev/null
CN_LANG=`echo $LANG | grep CN`
date=`date +%Y%m%d%H%M`
logfile=servercheck.txt

if [ "$CN_LANG" == "" ];
then
    cn=true
else
    cn=false
fi

rm $logfile

log() {
    echo "$1" >> $logfile
}

# 1.检查密码有效期设置
## 检查/etc/login.defs
echo " 1.检查密码有效期设置"
PASS_MAX_DAYS=`cat /etc/login.defs | grep "PASS_MAX_DAYS" | grep -v \# | awk '{print$2}'`
PASS_MIN_DAYS=`cat /etc/login.defs | grep "PASS_MIN_DAYS" | grep -v \# | awk '{print$2}'`
PASS_WARN_AGE=`cat /etc/login.defs | grep "PASS_WARN_AGE" | grep -v \# | awk '{print$2}'`
if [ "$PASS_MAX_DAYS" == "99999" ];
then
    log "1. 未配置密码超时时间,不安全"
    log "建议:"
    log "  执行 sed -i '/PASS_MAX_DAYS/s/99999/90/g' /etc/login.defs 设置密码的有效时间为90天"
else
    log "1. 已配置密码超时时间${PASS_MAX_DAYS},安全"
fi

# 2.检查密码强度检查配置
echo " 2.检查密码强度检查配置"
FIND=`cat /etc/pam.d/systemd-auth | grep 'passwd requisite pam_cracklib.so'`
if [ "$FIND" == "" ];
then
    log "2. 未配置密码强度检查,不安全"
    log "建议:"
    log "  执行 echo \"passwd requisite pam_cracklib.so difok=3 minlen=8 ucrediit=-1 lcredit=-1 dcredit=-1\">> /etc/pam.d/systemd-auth 设置密码需要包含大小写字母及数字，且长度至少为8"
else
    log "2. 已配置密码强度检查,安全"
fi

# 3.检查空口令账号
echo " 3.检查空口令账号"
NULLF=`awk -F: '($2 == "") {print $1}' /etc/shadow`
if [ "$NULLF" != "" ];
then
    log "3. 存在空密码账户,不安全"
    log "检查结果如下:"
    log "$NULLF"
    log "建议:"
    log "  上述账户无密码,使用passwd 命令添加密码"
else
    log "3. 未发现空密码账户,安全"
fi

# 4.检查账户锁定配置
echo " 4.检查账户锁定配置"
FIND=`cat /etc/pam.d/systemd-auth | grep 'auth required pam_tally.so'`
if [ "$FIND" == "" ];
then
    log "4. 未配置账户锁定策略,不安全"
    log "建议:"
    log "   执行 echo \"auth required pam_tally.so onerr=fail deny=10 unlock_time=300\" >> /etc/pam.d/systemd-auth 设置账户锁定，连续输错10次密码后，账户锁定5分钟"
    log "注:解锁账户执行 faillog -u <user> -r"
else
    log "4. 已配置账户锁定,安全"
fi


# 5.检查除root之外的账户UID为0
echo " 5.检查除root之外的账户UID为0"
mesg=`awk -F: '($3==0) { print $1 }' /etc/passwd | grep -v root`
if [ "$mesg" != "" ]
then
    log "5. 发现UID为0的账户,不安全"
    log "检查结果如下:"
    log "$mesg"
    log "建议:"
    log "   上述账户UID为0,执行下面的操作进行修改"
    log "   usermod -u <new-uid> <user>"
    log "   groupmod -g <new-gid> <user>"
else
    log "5. 未发现UID为0的账户,安全"
fi

# 6.检查环境变量包含父目录
echo " 6.检查环境变量包含父目录"
parent=`echo $PATH | egrep '(^|:)(\.|:|$)'`
if [ "$parent" != "" ]
then
    log "6. 环境变量中存在父目录,不安全"
    log "检查结果如下:"
    log "$parent"
    log "建议:"
    log "   环境变量中不要带有父目录(..)"
else
    log "6. 环境变量未包含父目录,安全"
fi

# 7.检查环境变量包含组权限为777的目录
echo " 7.检查环境变量包含组权限为777的目录"
part=`echo $PATH | tr ':' ' '`
dir=`find $part -type d \( -perm -002 -o -perm -020 \) -ls`
if [ "$dir" != "" ]
then
    log "7. 环境变量中包含组权限为777的目录"
    log "检查结果如下:"
    log "$dir"
    log "建议:"
    log "   上述目录权限过低,请使用chmod 命令修改目录权限"
else
    log "7. 未发现组权限为777的目录,安全"
fi

# 8.远程连接安全性
echo " 8.远程连接安全性"
netrc=`find / -name .netrc`
rhosts=`find / -name .rhosts`
failed="0"
if [ "$netrc" == "" ]
then
    if [ "$rhosts" == "" ]
    then
        log "8. 检查远程安全性通过,安全"
    else
        failed="1"
    fi
else
    failed="1"

fi
if [ "$failed" == "1" ]
then
    log "8. 检查远程连接安全性未通过,不安全"
    log "检查结果如下:"
    log "$netrc"
    log "$rhosts"
    log "建议:"
    log "   请和管理员联系上述文件是否必要,如非必要,应当删除"
fi

# 9.检查umask配置
echo " 9.检查umask配置"
bsetting=`cat /etc/profile /etc/bash.bashrc | grep -v "^#" | grep "umask"| awk '{print $2}'`
if [ "$bsetting" == "" ]
then
    log "9. umask 未配置,不安全"
    log "建议:"
    log "   执行 echo \"umask 027\" >> /etc/profile 增加umask配置"
else
    UMASK=`echo "$bsetting" | grep 027 | uniq`
    if [ "$UMASK" != "027" ]
    then
        log "9. umask 配置值不安全"
        log "检查结果如下:"
        log "umask $UMASK"
        log "建议:"
        log "   修改/etc/profile /etc/bash.bashrc 文件中的umask 命令为 \"umask 027\""
    else
        log "9. umask 已配置,安全"
    fi
fi

# 10.检查重要文件和目录的权限
echo "10.检查重要文件和目录的权限"
content=
p=`ls -ld /etc`
content=`echo -e "$content\n$p"`
p=`ls -ld /etc/rc*.d`
content=`echo -e "$content\n$p"`
p=`ls -ld /tmp`
content=`echo -e "$content\n$p"`
p=`ls -l  /etc/inetd.conf`
content=`echo -e "$content\n$p"`
p=`ls -l  /etc/passwd `
content=`echo -e "$content\n$p"`
p=`ls -l  /etc/group `
content=`echo -e "$content\n$p"`
p=`ls -ld /etc/security`
content=`echo -e "$content\n$p"`
p=`ls -l  /etc/services`
content=`echo -e "$content\n$p"`
log "10. 检查重要文件和目录的权限"
log "检查结果如下:"
log "$content"
log "建议:"
log "   请仔细检查以上文件和目录的权限,如果权限太低,请及时修改"


# 11.检查未授权的SUID/SGID文件
echo "11.检查未授权的SUID/SGID文件"
files=
for PART in `grep -v "^#" /etc/fstab | awk '($6 != "0") {print $2 }'`;
do
    FIND=`find $PART \( -perm -04000 -o -perm -02000 \) -type f -xdev -print`
    if [ "$FIND" != "" ]
    then
        files=`echo -e "$files\n$FIND"`
    fi
done
if [ "$files" != "" ]
then
    log "11. 发现存在SUID和SGID的文件"
    log "检查结果如下:"
    log $files
    log "建议:"
    log "   请检查上述目录/文件是否可疑,如果可疑,请及时删除"
else
    log "11. 未发现存在SUID和SGID的文件,安全"
fi

# 12.检查任何人都有写权限的目录
echo "12.检查任何人都有写权限的目录"
files=
for PART in `awk '($3 == "ext2" || $3 == "ext3" || $3 == "ext4") {print $2 }' /etc/fstab`;do
    FIND=`find $PART -xdev -type d \( -perm -0002 -a ! -perm -1000 \) -print`
    if [ "$FIND" != "" ]
    then
        files=`echo -e "$files\n$FIND"`
    fi
done
if [ "$files" != "" ]
then
    log "12. 发现任何人都有写权限的目录"
    log "检查结果如下:"
    log "$files"
    log "建议:"
    log "   请检查上述目录是否有必要任何人都可写,如非必要,请及时修改权限"
else
    log "12. 未发现任何人都有写权限的目录,安全"
fi


# 13.检查任何人都有写权限的文件
echo "13.检查任何人都有写权限的文件"
files=
for PART in `grep -v "#" /etc/fstab | awk '($6 != "0") {print $2 }'`; do 
    FIND=`find $PART -xdev -type f \( -perm -0002 -a ! -perm -1000 \) -print `
    if [ "$FIND" != "" ]
    then
        files=`echo -e "$files\n$FIND"`
    fi
done
if [ "$files" != "" ]
then
    log "13. 发现任何人都有写权限的文件"
    log "检查结果如下:"
    log "$files"
    log "建议:"
    log "   请检查上述文件是否有必要任何人都可写,如非必要,请及时修改权限"
else
    log "13. 未发现任何人都有写权限的文件,安全"
fi

# 14.检查没有属主的文件
echo "14.检查没有属主的文件"
files=
for PART in `grep -v "#" /etc/fstab | awk '($6 != "0") {print $2 }'`; do 
    FIND=`find $PART -nouser -o -nogroup -print `
    if [ "$FIND" != "" ]
    then
        files=`echo -e "$files\n$FIND"`
    fi
done
if [ "$files" != "" ]
then
    log "14. 发现没有属主的文件"
    log "检查结果如下:"
    log "$files"
    log "建议:"
    log "   请为上述文件增加属主,如有可疑文件,请及时删除"
else
    log "14. 未发现没有属主的文件,安全"
fi

# 15.检查异常的隐藏文件
echo "15.检查异常的隐藏文件"
files=
FIND=`find / -name "..*" -print -xdev `
if [ "$FIND" != "" ]
then
    files=`echo -e "$files\n$FIND"`
fi
FIND=`find / -name "...*" -print -xdev | cat -v`
if [ "$FIND" != "" ]
then
    files=`echo -e "$files\n$FIND"`
fi
if [ "$files" != "" ]
then
    log "15. 发现异常隐藏文件"
    log "检查结果如下:"
    log "$files"
    log "建议:"
    log "   请检查上述文件是否可疑,如果可疑,请及时删除"
else
    log "15. 未发现可疑隐藏文件,安全"
fi

# 16.检查登录超时设置
echo "16.检查登录超时设置"
tmout=`cat /etc/profile | grep -v "^#" | grep TMOUT `
if [ "$tmout" == "" ]
then
    log "16. 登录超时未配置,不安全"
    log "建议:"
    log "   执行 echo \"TMOUT=180\" >> /etc/profile 增加登录超时配置"
else
    log "16. 登录超时已配置,安全"
fi

# 17. 检查ssh 和telnet运行状态
echo "17.检查ssh 和telnet运行状态"
ssh=`service ssh status | grep running`
telnet=`service telnet status | grep running`
if [ "$ssh" != "" ] && [ "$telnet" == "" ]
then
    log "17. ssh telnet 状态正确,安全"
else
    log "17. ssh telnet 状态不正确,不安全"
    log "检查结果如下:"
    if [ "$ssh" == "" ]
    then
        log "   ssh 未运行, 建议安装并开启ssh服务"
    fi
    if [ "$telnet" != "" ]
    then
        log "   telnet 运行中, 建议停止telnet服务"
    fi
fi


# 18.root远程登录限制
echo "18.root远程登录限制"
permit=`cat /etc/ssh/sshd_config | grep -v "^#" | grep "PermitRootLogin" | awk "{print $2}"`
if [ "$permit" == "yes" ]
then
    log "18. 允许root远程登录,不安全"
    log "检查结果如下:"
    log "  PermitRootLogin $permit"
    log "建议:"
    log "  修改/etc/ssh/sshd_config文件, 将PermitRootLogin　的值改为 no"
else
    log "18. 不允许root远程登录,安全"
fi


# 19. 检查运行的服务
echo "19.检查运行的服务"
chkconfig=`which chkconfig`
bcheck=1
if [ "$chkconfig" == "" ]
then
    echo -n "19. 未安装chkconfig,是否安装 (y/n) :"
    read i
    case $i in
        y|yes)
            apt-get install -y sysv-rc-conf 
            cp /usr/sbin/sysv-rc-conf /usr/sbin/chkconfig
            echo "安装成功"
            ;;
        *)
            bcheck=0
            echo "未安装chkconfig,跳过此项检查"

            ;;
    esac
fi
if [ "$bcheck" != "0" ]
then
    level=`who -r | awk '{print $2}'`
    process=`chkconfig --list | grep "$level:on"`
    log "19. 当前开启服务检查完成"
    log "检查结果如下:"
    log "$process"
    log "建议:"
    log "   请检查上述服务,尽量关闭不必要的服务"
    log "   注:使用命令\"chkconfig --level $level <服务名>\" 进行关闭"
else
    log "19. 检查运行的服务,跳过"
fi

# 20. 检查core dump 状态 
echo "20.检查core dump 状态 "
SOFTFIND=`cat /etc/security/limits.conf | grep -v "^#" | grep "* soft core 0"`
HARDFIND=`cat /etc/security/limits.conf | grep -v "^#" | grep "* hard core 0"`
if [ "$SOFTFIND" != "" ] && [ "$HARDFIND" != "" ]
then
    log "20. core dump 检查正常,安全"
else
    log "20. core dump 检查不正常,不安全"
    log "建议:"
    log "   在/etc/security/limits.conf 文件中增加如下内容"
    log "   * soft core 0"
    log "   * hard core 0"
fi

# 21. 检查rsyslog状态
echo "21.检查rsyslog状态"
en=`systemctl is-enabled rsyslog`
conf=`cat /etc/rsyslog.conf | grep -v "^#" | grep "*.err;kern.debug;daemon.notice /var/adm/messages"`
if [ "$en" != "enabled" ]
then
    log "21. rsyslog未启动,不安全"
    log "建议:"
    log "   在/etc/rsyslog.conf中增加'*.err;kern.debug;daemon.notice /var/adm/messages'"
    log "   并执行以下命令:"
    log "   sudo mkdir /var/adm"
    log "   sudo touch /var/adm/messages"
    log "   sudo chmod 666 /var/adm/messages"
    log "   sudo systemctl restart rsyslog"
else
    if [ "$conf" == "" ];
    then
        log "21. 检查rsyslog配置"
        log "建议:"
        log "   在/etc/rsyslog.conf中增加'*.err;kern.debug;daemon.notice /var/adm/messages'"
        log "   并执行以下命令:"
        log "   sudo mkdir /var/adm"
        log "   sudo touch /var/adm/messages"
        log "   sudo chmod 666 /var/adm/messages"
        log "   sudo systemctl restart rsyslog"
    else
        log "21. 检查rsyslog配置,安全"
    fi
fi


echo "检查完成, 请仔细阅读${logfile}文件"
