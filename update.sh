#!/bin/bash
# Execute the following commands to allow scripts to execute!
#   chmod +x  FolderSetup.sh
#   chmod 755 FolderSetup.sh
#
# How to execute this script
#   bash your-script-name
#   sh your-script-name
#   ./your-script-name
#
# To get the exit status value of a script or app use
#   $?
########################################
#
# Master media update script
#
########################################
# Copyright 2020 Gareth Goslett
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
########################################

function Trim()
{
  local var=$@
  
  var="${var#"${var%%[![:space:]]*}"}"   # remove leading whitespace characters
  var="${var%"${var##*[![:space:]]}"}"   # remove trailing whitespace characters
  echo -n "$var"
}

ReadConfiguration()
{
  index=0
  
  while read line; do
    if [[ "$line" =~ ^[^#]*= ]]; then
      name[index]=$(Trim "${line%% =*}")
      value[index]=${line##*= }
      ((index++))
    fi
  done < /media/Bin/updateconfig.txt
}

function GetConfigurationValue()
{
  total=${#name[@]}
  
  for (( i=0; i<=$(( $total -1 )); i++ )); do
    if [ "${name[$i]}" == "$1" ]; then
      echo "${value[$i]}"
      break
    fi  
  done
}

function SecondsToDaysHoursMinutesSeconds()
{
  local seconds=$1
  local days=$(($seconds/86400))
  seconds=$(($seconds-($days*86400) ))
  local hours=$(($seconds/3600))
  seconds=$((seconds-($hours*3600) ))
  local minutes=$(($seconds/60))
  seconds=$(( $seconds-($minutes*60) ))
  
  if [ "$2" == "D" ]; then
    echo -n "${days}"
  else
    echo -n "${days}D ${hours}H ${minutes}M ${seconds}S"
  fi
}

function FileAge()
{
  echo $((`date +%s` - `stat -c %Z $1`))
}

FindEmptyFolders()
{
  if [ -d "$1" ]; then
    find "$1" -maxdepth 1 -mindepth 1 -type d -print0 | while IFS= read -r -d $'\0' folder; do
      name=$(basename "$folder")
      FindEmptyFolders "$1/$name"
    done
    
    empty=Y
    if [ "$(ls -A "$1")" ]; then
      empty=N
    fi
	
    if [ "$empty" == "Y" ]; then
      echo "  Delete: $1"
	  rmdir "$1"
    fi
  fi
 }
 
LinkSeriesFile()
{
  name=${3##*/}
  linked=false
  
  if [ -f "$3" ]; then
    nameuc="$(tr [a-z] [A-Z] <<< "$name")"
    fileext=${nameuc##*.}
    if [ "$fileext" == "ISO" ]; then
      filename="${nameuc%.*}"
      linkFile="$1/$filename.link.txt"
      if [ -e "$linkFile" ]; then
        until $linked; do
          read line || linked=true
            if ! [ "$line" == "" ]; then
              if ! [ -L "$2/$line" ]; then
                #echo "  Link Fake: $2/$line"
                ln -s -n "$3" "$2/$line"
              fi
            fi
        done < "$linkFile"
      fi
    fi
  fi
  
  if ! [ -L "$2/$name" ]; then
    #echo "  Link File: $2/$name"
    ln -s -n "$3" "$2/$name"
  fi
}

SynchronizeSeries()
{
  if [ "$(ls -A "$1")" ]; then # Only process non empty directories
    if ! [ -d "$2" ]; then
      echo "  Create Folder: $2"
      mkdir "$2"
	fi
	
    i=0
	
    for i in "$1"/*; do
      
	  name=${i##*/}
      
	  if [ -f "$i" ]; then
        LinkSeriesFile "$1" "$2" "$i"
      elif [ -d "$i" ]; then
        SynchronizeSeries "$i" "$2/$name"
      fi
    done
  fi
}

SynchronizeContent()
{
  isVideoSeries=N
  
  case $1 in
    *"/Video/Series/Dvd"*)       isVideoSeries=Y ;;
    *"/Video/Adult/SeriesDvd/"*) isVideoSeries=Y ;;
    *) ;;
  esac
  
  if [ "$isVideoSeries" == "Y" ]; then
    SynchronizeSeries "$1" "$2"
  else
    if [ -d "$1" ]; then
      
	  i=0
      
	  for i in "$1"/*; do
        name=${i##*/}
        if [ -f "$i" ]; then
          if ! [ -L "$2/$name" ]; then
            #echo "  Create Link: $2/$name"
            ln -s -n "$i" "$2/$name"
          fi
        fi
      done
      
      find "$1" -maxdepth 1 -mindepth 1 -type d -print0 | while IFS= read -r -d $'\0' folder; do
        
		name=$(basename "$folder")
        
		if [ "$(ls -A "$1/$name")" ]; then # Only process non empty directories
          if ! [ -d "$2/$name" ]; then
            echo "  Create Folder: $2/$name"
            mkdir "$2/$name"
          fi
          
		  SynchronizeContent "$1/$name" "$2/$name"
        fi
      done
    fi
  fi
}

function CheckBackupTarget()
{
  # $1 = Backup target path
  # $2 = Media mount points
  
  # Get the backup target disc
  IFS='/' read -ra parts <<< "$1"
  backupDisc=${parts[2]}
  
  # Set the initial result to fail
  result="1"
  
  # Find the target disc in the mounted media discs
  for disc in $2; do
    if [ "$backupDisc" == "$disc" ]; then
	  # Check that the target directory exists
	  if ! [ -d $1 ]; then
	    
		createPath="/${parts[1]}/${parts[2]}"
		max=${#parts[*]}
		max=$(($max-1))
		
		for i in $(seq 3 $max); do
		  
		  createPath="$createPath/${parts[$i]}"
		  
		  if ! [ -d $createPath ]; then
		    mkdir "$createPath"
		  fi
		done
	  fi
	  
	  result="0"  # Success
	fi
  done
  
  echo -n "$result" # Set the result
}

start=
end=

ShowStart()
{
  start=`date +%s`
  echo
  echo "$1"
}

ShowDone()
{
  end=`date +%s`
  runtime=$((end-start))
  echo "Done $runtime"
}

# 1) Read the media configuration file
ReadConfiguration
mediaFolder=$(GetConfigurationValue "MEDIAROOT")
MEDIADISKS=$(GetConfigurationValue "MEDIADISK")
MEDIAUSER=$(GetConfigurationValue "MEDIAUSER")
MEDIAGROUP=$(GetConfigurationValue "MEDIAGROUP")
MEDIAROOT=$(GetConfigurationValue "MEDIASHARE")
MEDIASYNC=$(GetConfigurationValue "MEDIAFOLDERS")
ISADMIN=N
GID="$(id -g)"

# Check if the administrator is executing this script
if [[ $EUID -eq 0 ]]; then
   ISADMIN=Y
else
  # Check that the script is executed by the correct user
  if [[ $UID -ne 1000 ]]; then
    echo "This script should be run as $MEDIAUSER, UID is not 1000"
    exit 0
  fi
  
  # Check that the script is executed by the correct group
  if [[ $GID -ne 1000 ]]; then
    echo "This script should be run as $MEDIAUSER, GID is not 1000"
    exit 0
  fi
fi

echo Media Library Manager 2.0
echo
echo "Media Share  :  [$MEDIAROOT]"
echo "Media Sync   :  [$MEDIASYNC]"
echo "Media Disks  :  [$MEDIADISKS]"
echo "Media Folder :  [$mediaFolder]"
echo "Media User   :  [$MEDIAUSER]"
echo "Media Group  :  [$MEDIAGROUP]"
echo "Current User :  [$USER  CID=$UID  GID=$GID  EID=$EUID]"
echo "Administrator:  [$ISADMIN]"

# 1) Verify that each media drive is mounted, if not remove it
ShowStart "Verifying that the media drives are mounted"
disktemp=$MEDIADISKS
for disk in $disktemp; do
  mountpoint -q $mediaFolder/$disk
  isMounted=$?
  if [[ $isMounted -ne 0 ]]; then
    echo "$mediaFolder/$disk is not mounted"
    MEDIADISKS=$(echo "${MEDIADISKS//$disk}")
  fi
done
ShowDone

# 2) Check that the media share directories exist
ShowStart "Verifying that the media share folders exist"
for kind in $MEDIASYNC; do
  source=$MEDIAROOT/$kind
  if ! [ -d "$source" ]; then
    echo "Creating media share folder: $source"
    mkdir "$source"
  fi
done
ShowDone

# 3) Delete the lost+found directories on media discs
if [ "$(GetConfigurationValue "CLEANLOST")" == "Y" ]; then
  if [ "$ISADMIN" == "Y" ]; then
    ShowStart "Deleting lost+found directories"
    for disk in $MEDIADISKS; do
      lost=$mediaFolder/$disk/lost+found
	  if [ -d "$lost" ]; then
	    rmdir "$lost"
	  fi
    done
    ShowDone
  fi
fi

# 4) Delete all broken symbolic links
if [ "$(GetConfigurationValue "CLEANLINKS")" == "Y" ]; then
  if [ "$ISADMIN" == "Y" ]; then
    ShowStart "Removing broken media links"
    for kind in $MEDIASYNC; do
      find "$MEDIAROOT/$kind" -type l -xtype l -delete
    done
    ShowDone
  fi
fi

# 5) Find and delete empty media directories
if [ "$(GetConfigurationValue "CLEANFOLDERS")" == "Y" ]; then
  if [ "$ISADMIN" == "Y" ]; then
    ShowStart "Removing empty media folders"
    for kind in $MEDIASYNC; do
      find "$MEDIAROOT/$kind" -maxdepth 1 -mindepth 1 -type d -print0 | while IFS= read -r -d $'\0' folder; do
        if [ -d "$folder" ]; then
          FindEmptyFolders "$folder"
        fi
      done
	done
    ShowDone
  fi
fi

# 6) Update directory ownership and permissions
if [ "$(GetConfigurationValue "FOLDERPERMS")" == "Y" ]; then
  if [ "$ISADMIN" == "Y" ]; then
    ShowStart "Updating directory permissions"
    for disk in $MEDIADISKS; do
      for kind in $MEDIASYNC; do
        source=$mediaFolder/$disk/$kind
		if [ -d "$source" ]; then
          echo "Setting folder permissions: $source"
          find "$source" -type d -exec chown $MEDIAUSER {} +
          find "$source" -type d -exec chgrp $MEDIAGROUP {} +
          find "$source" -type d -exec chmod 0775 {} +
		fi
      done
    done
    ShowDone
  fi
fi

# 7) Update file ownership and permissions
if [ "$(GetConfigurationValue "FILEPERMS")" == "Y" ]; then
  if [ "$ISADMIN" == "Y" ]; then
    ShowStart "Updating file permissions"
    for disk in $MEDIADISKS; do
      for kind in $MEDIASYNC; do
        source=$mediaFolder/$disk/$kind
		if [ -d "$source" ]; then
          echo "Setting file permissions: $source"
          find "$source" -type f -exec chown $MEDIAUSER {} +
          find "$source" -type f -exec chgrp $MEDIAGROUP {} +
          find "$source" -type f -exec chmod 0666 {} +
		fi
      done
    done
    ShowDone
  fi
fi

# If we are admin then exit now.
if [ "$ISADMIN" == "Y" ]; then
  #ShowStart "Updating media share permissions"
  #find "$MEDIAROOT" -type d -exec chown $MEDIAUSER {} +
  #find "$MEDIAROOT" -type d -exec chgrp $MEDIAGROUP {} +
  ##find "$MEDIAROOT" -type d -exec chmod 0775 {} +
  #find "$MEDIAROOT" -type l -exec chown $MEDIAUSER {} +
  #find "$MEDIAROOT" -type l -exec chgrp $MEDIAGROUP {} +
  ##find "$MEDIAROOT" -type l -exec chmod 0666 {} +
  #ShowDone
  echo
  echo "Administrative tasks done"
  exit 0
fi

# 8) Synchronize media folders and files
if [ "$(GetConfigurationValue "SYNCMEDIA")" == "Y" ]; then
  for kind in $MEDIASYNC; do
    ShowStart "Synchronizing $kind"
    for disk in $MEDIADISKS; do
      source=$mediaFolder/$disk/$kind
	  if [ -d "$source" ]; then
        target=$MEDIAROOT/$kind
        SynchronizeContent "$source" "$target"
	  fi
    done
    ShowDone
  done
fi

# 9) Generate media disc content lists
if [ "$(GetConfigurationValue "CONTENTLIST")" == "Y" ]; then
  ShowStart "Export disc content lists"
  contentTarget="$mediaFolder/Bin/ContentList4.txt"
  age=$(SecondsToDaysHoursMinutesSeconds $(FileAge "$contentTarget") "D")
  if [[ $age -lt 6 ]]; then
    echo "  List file is less than 6 days old, age is $(SecondsToDaysHoursMinutesSeconds $(FileAge "$contentTarget"))"
  else
   for i in $(seq 1 4); do
     oldNum=$(($i-1))
     contentTargetOld=$(echo "$mediaFolder/Bin/ContentList$i.txt")
     contentTargetNew=$(echo "$mediaFolder/Bin/ContentList$oldNum.txt")
 	if [ -f "$contentTargetOld" ]; then
       if [[ $i -eq 1 ]]; then
 	    rm $contentTargetOld
 	  else
 	    mv $contentTargetOld $contentTargetNew
 	  fi
 	fi
   done
   
   echo "List media content to $contentTarget"
   touch $contentTarget
   for kind in $MEDIASYNC; do
     for disk in $MEDIADISKS; do
       contentSource=$mediaFolder/$disk/$kind
 	  if [ -d "$contentSource" ]; then
         echo "  Source: $contentSource"
 		find "$contentSource" -type f >>$contentTarget
       fi
     done
   done
  fi
  ShowDone
fi

# 10) Process backup tasks
if [ "$(GetConfigurationValue "BACKUP")" == "Y" ]; then
  ShowStart "Process backups"
  
  # Backup important system information
  cp /etc/fstab           /media/Bin/bkup.fstab
  cp /etc/samba/smb.conf  /media/Bin/bkup.smb.conf
  
  # Process all configured backup tasks
  for i in $(seq 1 99); do
    cmd=`printf "BACKUP%02d" $i`
    line=$(GetConfigurationValue "$cmd")
    if [ "$line" != "" ]; then
      echo "$cmd"
	  IFS='*' read -a array <<< "$line"
	  backupSource="$mediaFolder/$(Trim ${array[0]})"
	  backupTarget="$mediaFolder/$(Trim ${array[1]})"
	  if ! [ -d "$backupSource" ]; then
        echo "  Source directory does not exist: $backupSource"
	  else
	    result=$(CheckBackupTarget "$backupTarget" "$MEDIADISKS")
		if [[ "$result" == "0" ]]; then
          echo "  Source: $backupSource"
          echo "  Target: $backupTarget"
          rsync -a -v "$backupSource" "$backupTarget"
		else
		  echo "  Error $result, invalid target disc: $backupTarget"
		fi
      fi
    fi
  done
  ShowDone
fi

# 11) Show statistics
if [ "$(GetConfigurationValue "STATISTICS")" == "Y" ]; then
  ShowStart "Statistics"
  
  dfargs=
  for disk in $MEDIADISKS; do
    dfargs+=" $mediaFolder/$disk"
  done
  
  df -h $dfargs
  echo
  
#  for kind in $MEDIASYNC; do
#    du -s -h -L "$MEDIAROOT/$kind"
#  done

  ShowDone
fi

exit 0
