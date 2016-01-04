#!/bin/bash
#
#
#
# Script to configure an AMI for Solr build
# Author        : MCG
# Date          : 23/11/2015
#
# Check to see if sysstat is installed already. If not, go get it.

#. /home/ec2-user/.aws/credentials

INSTANCEID=$(wget -q -O - http://instance-data/latest/meta-data/instance-id)
PUB_HOST=$(wget -q -O - http://instance-data/latest/meta-data/public-hostname)
AZ=$(wget -q -O - http://instance-data/latest/meta-data/placement/availability-zone)
REGION=$(echo ${AZ%?})
SOLRCONF=/var/solr/solr.in.sh
SOLRFILE=solr-5.2.1.tgz
S3LOC="s3://solr-build"
SVNLOC="https://sessioncam.svn.beanstalkapp.com/devops/branches/MCGSolrAMI/configs/solr-build"
SOLRSET=sessionfilterset.tgz
JAVAFILE=jdk-8u45-linux-x64.tar.gz
JDIR=jdk1.8.0_45
FILELIST="schema.xml solrconfig.xml solr.in.sh jetty.xml stopwords.txt"



function create_disk
{
  solrrc=0

  echo "Creating ${1}GB volume... "

  vol=$(aws ec2 create-volume --size ${1} --availability-zone ${AZ} --volume-type gp2 --region ${REGION} --output text)
   ((solrrc=solrrc+$?))
  volId=$(echo $vol | awk '{print $7}')
  echo "VolumeID is $volId"
   ((solrrc=solrrc+$?))
  echo "Waiting for volume ${volId} to be available..."
  aws ec2 wait volume-available --volume-ids ${volId} --region ${REGION}
   ((solrrc=solrrc+$?))
  echo "Attaching Volume..."
  aws ec2 attach-volume --volume-id ${volId} --instance-id ${INSTANCEID} --device ${3} --region ${REGION} 2>&1 >/dev/null
   ((solrrc=solrrc+$?))
  sleep 10 2>&1 >/dev/null
  mkdir ${2}
   ((solrrc=solrrc+$?))
  chmod 777 ${2}
   ((solrrc=solrrc+$?))
  echo "Formatting disk..."
  mkfs.ext4 ${3} 2>&1 >/dev/null
   ((solrrc=solrrc+$?))
  sleep 10 2>&1 >/dev/null
  mount ${3} ${2}
   ((solrrc=solrrc+$?))
  chmod 777 ${2}
   ((solrrc=solrrc+$?))
  sed -i -e "\$a${3}  ${2}   ext4   defaults  0   0" /etc/fstab
   ((solrrc=solrrc+$?))
  aws ec2 modify-instance-attribute --region ${REGION} --instance-id $INSTANCEID --block-device-mappings "[{\"DeviceName\":\"${3}\",\"Ebs\":{\"DeleteOnTermination\":true}}]"
   ((solrrc=solrrc+$?))

  ISMOUNT=$(df -h | grep -i ${3})

  if [[ $solrrc -ne 0 ]] || [[ -z ${ISMOUNT} ]]; then
   echo "Error creating and attachting volumes - please investigate"
  fi
}

rpm -qa | grep -i sysstat

if [[ $? -ne 0 ]]; then

        yum install -y sysstat 2>&1 >/dev/null

    if [[ $? -ne 0 ]]; then
    echo "Error installing sysstat - please investigate"

    exit 1

    fi

fi


create_disk 200 /solr /dev/xvdf
create_disk 10 /solrLog /dev/xvdg


# Get Solr

aws s3 cp ${S3LOC}/${SOLRFILE} /


#Extract files
cd /
tar xzf /${SOLRFILE} solr-5.2.1/bin/install_solr_service.sh --strip-components=2 2>&1 >/dev/null

#Install solr
bash /./install_solr_service.sh ${SOLRFILE} 2>&1 >/dev/null

#Check if solr is available
if [[ -z $(service solr status | grep startTime) ]]; then
 echo "ERROR: Solr has not started"
 exit 3
else
 chkconfig solr off

   if [[ $? -ne 0 ]]; then
   echo "INFO: chkconfig not turned off for solr - it may auto start on boot"
   fi 

fi

# Install Java
mkdir /opt/java
aws s3 cp ${S3LOC}/${JAVAFILE} /opt/java/${JAVAFILE}
tar -zxf /opt/java/${JAVAFILE} -C /opt/java
update-alternatives --install /usr/bin/java java /opt/java/${JDIR}/bin/java 1
alternatives --config java <<< '2'

# Download filter set and expand to /var/solr/data

if [[ ! -d $(ls -l /var/solr/data) ]]; then
 echo "Retrieving sessionfilterset from S3..."
 cd /var/solr/data
 aws s3 cp ${S3LOC}/${SOLRSET} .
 tar -zxf ${SOLRSET}
else
 echo "ERROR: /var/solr/data does not exist"
 exit 2
fi


# Limits

aws s3 cp ${S3LOC}/limits /
sed -i '/End of file/d' /etc/security/limits.conf
cat /limits >> /etc/security/limits.conf
sed -i -e "\$a# End of file" /etc/security/limits.conf

# Grab config from svn

rpm -qa | grep svn

if [[ $? -ne 0 ]]; then
 yum install svn -y
fi

cd /
svn checkout --username SessionCamBuild --password aech5Iet --depth files ${SVNLOC} --non-interactive

cd /solr-build  


FILECP=0

alias | grep cp

if [[ $? -eq 0 ]]; then
  CPALIAS=1
  unalias cp
else
  echo "cp alias not found"
fi

for FILE in ${FILELIST}
do 
  case ${FILE} in
    schema.xml | solrconfig.xml )
      PERMS=644
      OWNER=ec2-user
      GROUP=ec2-user
      FPATH=/var/solr/data/sessionfilterset/conf
      ;;
    solr.in.sh ) 
      PERMS=755
      OWNER=solr
      GROUP=solr
      FPATH=/var/solr
      ;;
    stopwords.txt )  
      PERMS=664
      OWNER=ec2-user
      GROUP=ec2-user
      FPATH=/var/solr/data/sessionfilterset/conf
      ;;
    jetty.xml )
      PERMS=664
      OWNER=ec2-user
      GROUP=ec2-user
      FPATH=/opt/solr-5.2.1/server/etc
      ;;
  esac
 
  cp -f ${FILE} ${FPATH}
 ((FILECP=FILECP+$?))
  chown ${OWNER}.${GROUP} ${FPATH}/${FILE}
 ((FILECP=FILECP+$?))
  chmod ${PERMS} ${FPATH}/${FILE}
 ((FILECP=FILECP+$?))
done

if [[ ${FILECP} -ne 0 ]]; then
	echo "Solr config files not copied correctly"
	exit 3
fi

if [[ `echo ${CPALIAS}` -eq 1 ]]; then
  alias cp='cp -i'
fi

# Complete with a yum update
yum update -y

if [[ $? -ne 0 ]]; then
 echo "ERROR: Unable to complete a yum update - please check"
fi

echo "UserData Complete!"
exit 0

