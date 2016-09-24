#!/bin/bash


#------------------  ----Cz Li's Script--------------------------
#-------------Automatically Install Driver on Y50----------------
#---------Procedure&Tools Original Created by RehabMan-----------
#
#set -x


#
#Public variables
resPath=$(cd `dirname $0`; pwd)
cd ~/
usrPath=$PWD
workPath=$usrPath/Projects/y50.git
cpPath=$usrPath/Projects/res
cmd1=$1
cmd2=$2
cmd3=$3
errcount=0
#err=0


#
#Ensure sudo
if [[ "$(id -u)" != "0" ]]; then   #Verify sudo
    echo "此命令需要superuser权限, 请运行: 'sudo $0 $@'"
    exit 1
#    echo "此脚本需要superuser权限, 请输入密码."
#    sudo $0 $@
#    exit $?
fi

#
#Pre-Procedure Functions
function _BREAK()
{
case $1 in
  0 )
    return 0
;;
  22 )
    read -p ${2}"按回车键跳过..."
    return 1
;;
  2 )
    read -p ${2}"按回车键退出."
    exit 2
;;
  "-p" )
  read -p ${2}"按回车键继续..."
;;
  "" )
  read -p "按回车键继续..."
;;
  * )
    return 2
;;
esac
}





#
#模块函数
function _mountEFI()   
{
#efinode=$"/dev/"$(diskutil list / | sed  '1d' | awk '{if($2=="EFI") print $6}')
#local efitmp=$(echo $efinode | sed 's/[0-9]//g')
#[[ $efitmp != "/dev/disks" ]] && echo "Warning: No EFI Partition Found!" && return 2
#mkdir /Volumes/EFI
#diskutil mount -mountPoint /Volumes/EFI $efinode


[[ $installed != 1 ]] && return 2
if [ -f ${workPath}/mount_efi.sh ]; then
EFIPath=$(sudo ${workPath}/mount_efi.sh) && local tmp=$?
efinode=$(mount | grep " /Volumes/EFI " |awk '{print $1}')
return $tmp
fi
return 2
}


function _chkFile ()
{
echo "正在检查资源文件..."
[[ $resPath = "" ]] && return 2
cd $resPath
local res_md5=0
[[ -f ./res.tar.gz ]] && res_md5=`md5 -q ./res.tar.gz`
case $res_md5 in
"6199ce7fffac568ecb9f8f4954334631" )
   scriptver="0.5"
   echo "Version: ""$scriptver"" alpha"
;;
"84696720e1cb90f85ea70509fada2091" )
scriptver="0.8"
echo "Version: ""$scriptver"" beta"
;;
"93bb3714e3d46983f8324c76c349843d" )
scriptver="0.9"
echo "Version: ""$scriptver"" release"
;;
0 )
   echo  "资源文件不存在."
   return 2
;;
* )
   echo "校验失败, 请重新下载文件."
   return 2
;;
esac
sleep 2
}



function _chkSIP()  ##The csrutil tool is only available for 10.11+
{
SIPAll=$(csrutil status | grep "System Integrity Protection status" | awk '{print $5}')
SIPKext=$(csrutil status | grep "Kext Signing" | awk '{print $3}')
SIPFile=$(csrutil status | grep "Filesystem Protections" | awk '{print $3}')
SIPNVRAM=$(csrutil status | grep "NVRAM Protections" | awk '{print $3}')
}


function _chkDiskSpace()  
{
local devnode=${1}
local SpaceDesired=${2}
local SpaceAvilable=$(df -m $devnode |sed -n 2p | awk '{print $4}')
[[ $SpaceAvilable -ge $SpaceDesired ]] && return 0
return 2
}


function _chkSysVer()
{
SysVer=$(sw_vers -productVersion)
echo "系统版本: "$SysVer
case $SysVer in
"10.10"|"10.10.1" )
echo "此脚本仅适用于10.10.2+"
return 2
;;
"10.10.2"|"10.10.3"|"10.10.4"|"10.10.5" )
SubSysVer="10.10"
;;
"10.11"|"10.11.1" )
SubSysVer="10.11"
;;
* )
echo "此脚本不适用于该系统版本"
return 2
;;
esac
}


function _chkIfCanRun()
{
_chkFile
_BREAK $?
_chkSysVer
_BREAK $?
_chkDiskSpace / 1900
[[ $? = 2 ]] && echo "错误: 系统分区可用空间不足" && echo "请保证系统分区拥有2.0GB以上的可用空间" && _BREAK 2
[[ $SubSysVer = "10.11" ]] && _chkSIP
if [[ $SIPKext = "enabled" ]] || [[ $SIPFile = "enabled" ]]; then
echo "错误: SIP系统保护未关闭, 无法写入系统文件或安装kext, 请关闭SIP后重试."
_BREAK 2
fi
#_chkDiskSpace $efinode 19
}


function _ERRMSG_DSDT()
{
clear
echo "DSDT提取/编译失败..."
echo "请使用正确的Clover配置"
echo "请确保Clover未注入DSDT"
echo "请尝试使用U盘Clover启动..."
_BREAK 2
}


function _ERRMSG_IOKIT()
{
clear
echo "IOKit提取失败..." 
_BREAK 2
}




#Install prepared files
function _ERRMSG_NETWORKERR()
{
clear
echo ${1}
case $errcount in
0|1|2|3 )
if [[ $errcount != 3 ]]; then
    echo "是否重试? (重试次数: $errcount/3 )"
    read -p "(y/n):" yn
    case $yn in
    y|Y|yes|Yes|YES )
    errcount=$(expr $errcount + 1)
    ${2}
    ;;
    * )
    _BREAK 2
    ;;
    esac
else
    echo "重试次数: $errcount/3"
    echo "重试次数已达上限."
    errcount=0
    _BREAK 2
fi
;;
* )
errcount=0
_ERRMSG_NETWORKERR $@
;;
esac
}


function _chkNet()
{
lost_rate=`ping -c 8 -W 10 github.com | grep 'packet loss' | awk -F'packet loss' '{ print $1 }' | awk '{ print $NF }' | sed 's/%//g'`
if [[ $lost_rate = "100.0" ]] || [[ $lost_rate = "" ]]; then
_ERRMSG_NETWORKERR "网络连接失败, 请检查网络..." _chkNet
return $?
fi
[[ $lost_rate != "0.0" ]] && echo "网络环境不稳定，请注意"\!" (当前丢包率: ${lost_rate}%)" && sleep 2 && return 2
[[ $lost_rate = "0.0" ]] && return 0
return 23
}


function _wait()
{
local timeout=${3}
while true; do
ps -p $1 >/dev/null 2>&1
[[ $? -eq 1 ]] && return 0
sleep 1 && clear && echo ${4} && cat ~/tmp.log
timeout=$(expr $timeout - 1)
echo "下载倒计时: "$timeout" 秒"
[[ $timeout -lt 1 ]] && sleep 1 && return 1
continue
done
}


function _Install_Repository()
{
local timeout=1200
rm -rf ~/tmp.log && rm -rf ~/sign
[[ ${2} = "" ]] && return 2
timeout=${3}
(git clone https://github.com/RehabMan/${1} ${2} >~/tmp.log 2>&1; echo 0 >~/sign) & cmd_pid=$!
(sleep $timeout; kill -9 $cmd_pid &>/dev/null; echo 2 >~/sign) & mon_pid=$!
_wait $cmd_pid $mon_pid $timeout "正在下载 ${1}..."
kill -9 $mon_pid &>/dev/null
sign=$(cat ~/sign | sed -n '1p')
rm -f ~/tmp.log && rm -f ~/sign
[[ $sign -eq 0 ]] && return 0
[[ $sign -eq 2 ]] && return 2
return 1
}


function _Retrive_File()
{
sleep 2
local tmp=1
cd ${usrPath}/Projects && rm -rf ./laptop.git && rm -rf ./y50.git && tmp=0
_chkNet
[[ $tmp -eq 0 ]] && _Install_Repository "Laptop-DSDT-Patch" "laptop.git" 900 && _Install_Repository "Lenovo-Y50-DSDT-Patch" "y50.git" 900
if [ -f ./y50.git/makefile ] && [ -d ./laptop.git ];then
return 0
else
_ERRMSG_NETWORKERR "文件下载失败..." _Retrive_File
fi
}


#Install Command Line Tools

function _chkEnv()
{
local pkg=$(pkgutil --pkgs | grep "com.apple.pkg.CLTools_Executables")
if [[ $pkg = "com.apple.pkg.CLTools_Executables" ]]; then
return 0
fi
return 2
}


function _Install_CLT()
{
_chkEnv
case $? in
0 )
echo "命令行工具已安装.(2/4)"
return 0
;;
2 )
echo -e "正在安装命令行工具...(2/4)"/c
sudo installer -pkg ${cpPath}/CLT-10.10.pkg -target / >/dev/null 2>&1
echo "完成"
;;
esac
_chkEnv && echo "安装成功." && return 0
return 2
}

#Install all steps
function _Install_File()
{
[[ $resPath = "" ]] || [[ $usrPath = "" ]] && return 2
echo "正在配置资源文件...(1/4)"
cd $resPath && rm -rf ${usrPath}/Projects && mkdir ${usrPath}/Projects && cp ./res.tar.gz ${usrPath}/Projects/res.tar.gz
cd ${usrPath}/Projects/ && tar -xf ./res.tar.gz && rm -f ./res.tar.gz
[[ -f ./res.tar.gz ]] && return 2
_Install_CLT
[[ $? != 0 ]] && echo "CLT Install Failed." && _BREAK 2
echo "正在下载内容... 来自github.com(3/4)"
_Retrive_File
echo "正在安装文件...(4/4)"
cd $workPath && rm -rf ./downloads/ && cp -r ../res/downloads/ ./downloads/ && sudo ./install_downloads.sh >/dev/null 2>&1
sudo cp $cpPath/patch-iokit /usr/bin/ && sudo chmod +x /usr/bin/patch-iokit
installed=1
}


#Function help myself auto pack
function _buildRes()
{
:
#cd ~/Projects/
#[[ -f ./res.tar.gz ]] && echo "Already exist please remove." && return 2
#find ./res/ -name .DS_Store | xargs rm -rf
#tar -czf res.tar.gz res
#md5 -q res.tar.gz
}




#Install Clover to EFI
function _Install_Clover()
{
_mountEFI
[[ $? -eq 2 ]] && echo "mountefi.sh not handled." && return 4
[[ $EFIPath = "" ]] || [[ $efinode = "" ]] && return 2
_chkDiskSpace $efinode 19
[[ $? -eq 2 ]] && echo "错误: EFI分区可用空间不足" && echo "请保证EFI分区拥有20MB以上的可用空间" && _BREAK 2
[[ $EFIPath = "" ]] && return 2
if [[ -d ${EFIPath}/CLOVER_BAK ]]; then
echo "备份Clover失败, 指定的Clover备份文件夹已存在(${EFIPath}/CLOVER_BAK)."
echo "请手动备份Clover文件夹(${EFIPath}/EFI/CLOVER)."
read -p "按回车键后将覆盖Clover文件夹: "
rm -rf ${EFIPath}/EFI/CLOVER
else
rm -rf ${EFIPath}/CLOVER_BAK && mv -f ${EFIPath}/EFI/CLOVER ${EFIPath}/CLOVER_BAK
fi
[[ $? -eq 0 ]] && cp -r ${cpPath}/CLOVER/ ${EFIPath}/EFI/CLOVER/ && rm -rf ${EFIPath}/EFI/CLOVER/config.plist
[[ $? -eq 0 ]] && _selectConfig && return $?
return 2
}


function _selectConfig()
{
read -p "您的屏幕分辨率是否为4K? 请输入yes/no:" yn1
case $yn1 in
y|Y|yes|Yes|YES )
echo "已选择4k_UHD配置文件."
cp -r ${workPath}/config_UHD.plist ${EFIPath}/EFI/CLOVER/config.plist
;;
n|N|no|No|NO )
echo "已选择1080P配置文件."
cp -r ${workPath}/config.plist ${EFIPath}/EFI/CLOVER/config.plist
;;
* )
echo "您输入的内容不正确, 请重新输入." && sleep 1
_selectConfig
;;
esac
}


#Inject Display EDID (Manual Steps)
function _InjectEDID()
{
clear
echo "正在导入EDID..."
echo "请在打开的应用程序中做以下操作: "
echo "点击 'Open EDID binary file...' 并打开准备好的 EDID.hex 文件."
echo "选择'Apple MacBook Pro Display'."
echo "点击 make 按钮."
_BREAK -p "请在阅读完成后"
echo "正在打开程序..."
open ${cpPath}/FixEDID.app
_BREAK -p "请在操作完成后"
find /Users/licz/Desktop/ -name 'DisplayVendorID*'
cd 
local EDIDTemp=$( find ./DisplayVendorID*/ | sed -n '1p' )
EDIDDir=$( echo $EDIDTemp | sed -e '1s/.//' )
if [ -d ~/Desktop$EDIDDir ];then
rm -rf /System/Library/Displays/Overrides$EDIDDir
cp -r ~/Desktop$EDIDDir/ /System/Library/Displays/Overrides$EDIDDir
echo "完成"
else
_BREAK 1 "本地EDID文件不存在, "
fi
}


#Disassemble & Patch DSDT
function _InjectDSDT()
{
cd $workPath
echo "正在执行DSDT/SSDT patch及编译..."
make cleanallex
./disassemble.sh
make patch
make
local tmp1=1
[ -f ./build/DSDT.aml ] && [ -f ./build/SSDT-1.aml ] && [ -f ./build/SSDT-2.aml ] && [ -f ./build/SSDT-3.aml ] && tmp1=0
local tmp2=1
[ -f ./build/SSDT-4.aml ] || [ -f ./build/SSDT-9.aml ] && tmp2=0
if [[ $tmp1 -eq 0 ]] && [[ $tmp2 -eq 0 ]]; then
echo "DSDT编译成功, 正在注入Clover..."
make install
echo "完成" && return 0
fi
_ERRMSG_DSDT
_BREAK 2
}

#运行ssdtPRGen
function _getCPUBrand()
{
gBrandString=$(echo `sysctl machdep.cpu.brand_string` | sed -e 's/machdep.cpu.brand_string: //')
local data=($gBrandString)
CPUBrand="Intel"
[[ "${data[0]}" != "Intel(R)" ]] && CPUBrand="Unknown" && return 2
[[ "${data[3]}" = "CPU" ]] && CPUBrand="${data[2]}"
[[ "${data[2]}" = "CPU" ]] && CPUBrand="Xeon"
}

function _InjectBoost()
{
local errcode=0
_getCPUBrand
echo "处理器型号: "$gBrandString
echo "正在注入处理器变频..."
cd ${cpPath} && chmod +x ./ssdtPRGen.sh
[[ $? != 0 ]] && return 2
case $CPUBrand in
"i7-4720HQ" )
    ./ssdtPRGen.sh -p 'i7-4710HQ' -f 2600 -turbo 3600 >/dev/null 2>&1
;;
"i7-4710HQ" | "i7-4700HQ" | "i5-4210H" | "i5-4200H" )
    ./ssdtPRGen.sh >/dev/null 2>&1
;;
* )
    ./ssdtPRGen.sh >/dev/null 2>&1
    echo "错误: 不适配的CPU型号"\!
;;
esac
if [ -f ~/Library/ssdtPRGen/SSDT.aml ] && [ $CPUBrand != "Unknown" ]; then
    [[ $EFIPath != "/Volumes/EFI" ]] && _mountEFI
    [[ $? -eq 2 ]] && return 4
    rm -rf $EFIPath/EFI/CLOVER/ACPI/patched/SSDT.aml
    cp ~/Library/ssdtPRGen/SSDT.aml $EFIPath/EFI/CLOVER/ACPI/patched/SSDT.aml && echo "完成" && return 0
    _BREAK 1 "注入失败, "
else
    _BREAK 1 "注入失败, "
fi
}



#运行iokit patch, 来自darkvoid
function _patchIOKit()
{
echo "正在运行IOKit Patch, 来自the-darkvoid..."
local iokit_md5=$(md5 -q "/System/Library/Frameworks/IOKit.framework/Versions/Current/IOKit")
case $SysVer in
  "General" | "10.10.5" | "10.10.2" | "10.10.3" | "10.10.4" | "10.11" | "10.11.1" )
      echo "${GREEN}[IOKit]${OFF}: Patching IOKit for maximum pixel clock"
      echo "${BLUE}[IOKit]${OFF}: Current IOKit md5 is ${BOLD}${iokit_md5}${OFF}"
      patch-iokit -patch
  ;;
  * )
      echo "错误: 不支持的系统版本 "$SysVer
      echo -e "May cause DAMAGE on your machine. Still want to continue? \c"
      read -p "(y/n): " yn2
      case $yn2 in
      y|Y|yes|Yes|YES )
          SysVer="General"
          _patchIOKit
          return $?
      ;;
      esac
      return 2
  ;;
esac
}


#删除驱动，安装仿冒声卡驱动及安卓网卡驱动
function _kextCleanup()
{
echo "正在优化驱动..."
cd /System/Library/Extensions/
rm -rf AMD*
rm -rf ATI*
rm -rf NV*
rm -rf GeForce*
rm -rf AppleIntelHD3*
rm -rf AppleIntelHD4*
}

function _InjectFakeHDA ()
{
local SLEpath="/System/Library/Extensions"
cd ${SLEpath}/
mkdir bak
mv ./AppleHDA.kext ./bak/AppleHDA.kext
mv AppleHDA* ./bak/AppleHDA*
mv VoodooHDA* ./bak/VoodooHDA*
mv HDAEnabler* ./bak/HDAEnabler*
#rm -rf HoRNDIS*
cd $cpPath
cp -r ./kexts/AppleHDA.kext ${SLEpath}/AppleHDA.kext
chown root:wheel ${SLEpath}/AppleHDA.kext
chown root:wheel ${SLEpath}/AppleHDA.kext/*
chown root:wheel ${SLEpath}/AppleHDA.kext/*/*
chown root:wheel ${SLEpath}/AppleHDA.kext/*/*/*
chown root:wheel ${SLEpath}/AppleHDA.kext/*/*/*/*
chown root:wheel ${SLEpath}/AppleHDA.kext/*/*/*/*/*
chown root:wheel ${SLEpath}/AppleHDA.kext/*/*/*/*/*/*
#cp -r ./kexts/HoRNDIS.kext ${SLEpath}/HoRNDIS.kext
cp -r ./kexts/HDAEnabler3.kext ${SLEpath}/HDAEnabler3.kext
chown root:wheel ${SLEpath}/HDAEnabler3.kext
chown root:wheel ${SLEpath}/HDAEnabler3.kext/*
chown root:wheel ${SLEpath}/HDAEnabler3.kext/*/*
chown root:wheel ${SLEpath}/HDAEnabler3.kext/*/*/*
_FixKext
}

function _FixKext()
{
sudo touch /System/Library/Extensions
echo -e "正在更新kextcache..."/c
sudo kextcache -u / >/dev/null 2>&1
[[ $? -eq 0 ]] && echo "完成" && return 0
sudo touch /System/Library/Extensions
echo -e "正在更新kextcache..."/c
sudo kextcache -u / >/dev/null 2>&1
[[ $? -eq 0 ]] && echo "完成" && return 0
return 1
}


function _main()
{
_Install_File
_Install_Clover
_InjectDSDT
_InjectBoost
_patchIOKit
_InjectFakeHDA
}

_chkIfCanRun

case $1 in
"" )
_main
;;
"-ver" )
exit 0
;;
"-refresh" )
exit 0
;;
"-clean" )
exit 0
;;
* )
exit 2
;;
esac


exit 0

