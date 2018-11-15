#!/bin/bash

### LICENSE - (BSD 2-Clause) // ###
#
# Copyright (c) 2018, Daniel Plominski (ASS-Einrichtungssysteme GmbH)
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without modification,
# are permitted provided that the following conditions are met:
#
# * Redistributions of source code must retain the above copyright notice, this
# list of conditions and the following disclaimer.
#
# * Redistributions in binary form must reproduce the above copyright notice, this
# list of conditions and the following disclaimer in the documentation and/or
# other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
# ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
# ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
### // LICENSE - (BSD 2-Clause) ###

### ### ### ASS // ### ### ###

#// get container ip address
GET_INTERFACE=$(netstat -rn | grep "0.0.0.0 " | grep "UG" | tr ' ' '\n' | tail -n 1)
GET_IPv4=$(ip addr show dev "$GET_INTERFACE" | grep "inet" | head -n 1 | awk '{print $2}')
GET_IPv6=$(ip addr show dev "$GET_INTERFACE" | grep "inet6" | head -n 1 | awk '{print $2}')

#// get active-directory credentials
GET_MAILBOT_AD_USER=$(cat /mailbot_ad_user_credential)
GET_MAILBOT_AD_PW=$(cat /mailbot_ad_pw_credential)

#// get mailserver address
GET_MAILSERVER=$(cat /mailbot_server)

#// exclude USERS
EXCLUDE_USERS=$(cat /mailbot_exclude)

#// PATTERN MATCHING
CONTENT_PATTERN_AD="aktiviere|Aktiviere|aktivieren|Aktivieren|aktivierung|Aktivierung|activate|Activate|enable|Enable|deaktiviere|Deaktiviere|deaktivieren|Deaktivieren|deaktivierung|Deaktivierung|deactivate|Deactivate|disable|Disable"
CONTENT_PATTERN_A="aktiviere|Aktiviere|aktivieren|Aktivieren|aktivierung|Aktivierung|activate|Activate|enable|Enable"
CONTENT_PATTERN_D="deaktiviere|Deaktiviere|deaktivieren|Deaktivieren|deaktivierung|Deaktivierung|deactivate|Deactivate|disable|Disable"
CONTENT_PATTERN_SCHEMA="von|zu|nach|an|Von|from|From|Zu|Nach|An|to|To"
CONTENT_PATTERN_MAIL_DOMAIN="mydomain.de|mydomain.com"

#// FUNCTION: spinner (Version 1.0)
spinner() {
   local pid=$1
   local delay=0.01
   local spinstr='|/-\'
   while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
         local temp=${spinstr#?}
         printf " [%c]  " "$spinstr"
         local spinstr=$temp${spinstr%"$temp"}
         sleep $delay
         printf "\b\b\b\b\b\b"
   done
   printf "    \b\b\b\b"
}

#// FUNCTION: run script as root (Version 1.0)
check_root_user() {
if [ "$(id -u)" != "0" ]; then
   echo "[ERROR] This script must be run as root" 1>&2
   exit 1
fi
}

#// FUNCTION: check state (Version 1.0)
check_hard() {
if [ $? -eq 0 ]
then
   echo "[$(printf "\033[1;32m  OK  \033[0m\n")] '"$@"'"
else
   echo "[$(printf "\033[1;31mFAILED\033[0m\n")] '"$@"'"
   sleep 1
   exit 1
fi
}

#// FUNCTION: check state without exit (Version 1.0)
check_soft() {
if [ $? -eq 0 ]
then
   echo "[$(printf "\033[1;32m  OK  \033[0m\n")] '"$@"'"
else
   echo "[$(printf "\033[1;33mWARNING\033[0m\n")] '"$@"'"
   sleep 1
fi
}

#// FUNCTION: check state hidden (Version 1.0)
check_hidden_hard() {
if [ $? -eq 0 ]
then
   return 0
else
   #/return 1
   checkhard "$@"
   return 1
fi
}

#// FUNCTION: check state hidden without exit (Version 1.0)
check_hidden_soft() {
if [ $? -eq 0 ]
then
   return 0
else
   #/return 1
   checksoft "$@"
   return 1
fi
}

#// FUNCTION: set new hosts config (ignore ::1 localhost ip6 lx-zone bind for documentserver)
set_lx_hosts_config() {
LXZONE=$(uname -a | egrep -c "BrandZ virtual linux")
if [ "$LXZONE" = "1" ]
then
cat << "HOSTS" > lx_hosts

127.0.0.1   localhost
::1         ip6-localhost ip6-loopback
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters

# EOF
HOSTS
   sudo cp -fv lx_hosts /etc/hosts
fi
}

#// FUNCTION: package install
install_package() {
   sudo apt-get autoclean
   sudo apt-get clean
   sudo apt-get update
   sudo DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confold" install --yes --force-yes "$@"
}

#// FUNCTION: mailbot
mailbot() {
   #// get latest mail index id
   FETCH_LAST_ID=$(curl --insecure --url "imaps://$GET_MAILSERVER/INBOX" --user "$GET_MAILBOT_AD_USER:$GET_MAILBOT_AD_PW" --request "EXAMINE INBOX" -s | grep "UIDNEXT" | awk '{print $4}' | sed 's/[^0-9]*//g')
   GET_LAST_ID=$(echo "$(($FETCH_LAST_ID-1))")
   if [ -z "$GET_LAST_ID" ]
   then
      echo "[$(printf "\033[1;31mFAILED\033[0m\n")] can't fetch latest mail index id!"
      exit 1
   else
      echo "[$(printf "\033[1;32m  OK  \033[0m\n")] successful fetch latest mail index id"
   fi
   #// save latest mail index id
   if [ -f /mailbot_id ]
   then
      GET_CURRENT_ID_FILE=$(cat /mailbot_id)
      echo "show mail index id: current $GET_CURRENT_ID_FILE"
      echo "show mail index id: latest $GET_LAST_ID"
   else
      echo "$GET_LAST_ID" > /mailbot_id
      echo "create file and show mail index id: latest $GET_LAST_ID"
   fi
   #// compare mail index id
   GET_CURRENT_ID=$(cat /mailbot_id)
   if [ "$GET_LAST_ID" == "$GET_CURRENT_ID" ]
   then
      echo "[$(printf "\033[1;32m  OK  \033[0m\n")] mail index id match, nothing to do!"
      exit 0
   else
      echo "[$(printf "\033[1;33mWARNING\033[0m\n")] mail index id mismatch, run evaluation"
      #// RUN evaluation
      sleep 1
      #// fetch mail content
      curl --insecure --url "imaps://$GET_MAILSERVER/INBOX;UID=$GET_LAST_ID" --user "$GET_MAILBOT_AD_USER:$GET_MAILBOT_AD_PW" -s > /mailbot_content
      check_hard fetch mail content
      ### ### ###
      #// parse mail content
      GET_SUBJECT=$(grep "Subject:" /mailbot_content | sed 's/\[ASS-Einrichtungssysteme GmbH\]//g' | sed 's/Zuweisung://g' | sed 's/Aktualisierung://g' | sed 's/Subject://g' | sed 's/ //g')
      GET_SUBJECT_MOD="${GET_SUBJECT/$'\r'/}"
      case $GET_SUBJECT_MOD in
      mailweiterleitung|Mailweiterleitung|mailforwarding|Mailforwarding)
         #// parse mail content structure
         CHECK_CONTENT_1=$(grep -A60 "Subject:" /mailbot_content | egrep "$CONTENT_PATTERN_AD" | egrep "$CONTENT_PATTERN_SCHEMA" | wc -l)
         if [ "$CHECK_CONTENT_1" = "1" ]
         then
            #// activation
            CHECK_CONTENT_A_1=$(grep -A60 "Subject:" /mailbot_content | egrep "$CONTENT_PATTERN_A" | egrep "$CONTENT_PATTERN_SCHEMA" | wc -l)
            if [ "$CHECK_CONTENT_A_1" = "1" ]
            then
               echo "[$(printf "\033[1;33mWARNING\033[0m\n")] run activation"
               STAGE="ACTIVATION"
            fi
            #// deactivation
            CHECK_CONTENT_D_1=$(grep -A60 "Subject:" /mailbot_content | egrep "$CONTENT_PATTERN_D" | egrep "$CONTENT_PATTERN_SCHEMA" | wc -l)
            if [ "$CHECK_CONTENT_D_1" = "1" ]
            then
               echo "[$(printf "\033[1;33mWARNING\033[0m\n")] run deactivation"
               STAGE="DEACTIVATION"
            fi
         else
            echo "[$(printf "\033[1;31mFAILED\033[0m\n")] find multiple content matches!"
            exit 1
         fi
      ;;
      *)
         echo "[$(printf "\033[1;31mFAILED\033[0m\n")] Subject doesn't match!"
         exit 1
      ;;
      esac
      ### ### ###
   fi
}

#// FUNCTION: mailbot forward activation
activation() {
   echo "... activation ..."
   #// check format
   CHECK_CONTENT_A_2=$(grep -A60 "Subject:" /mailbot_content | egrep "$CONTENT_PATTERN_A" | egrep "$CONTENT_PATTERN_SCHEMA" | tr ' ' '\n' | wc -l)
   if [ "$CHECK_CONTENT_A_2" = "5" ]
   then
      #// check format
      GET_CONTENT_FROM_A_1=$(grep -A60 "Subject:" /mailbot_content | egrep "$CONTENT_PATTERN_A" | egrep "$CONTENT_PATTERN_SCHEMA" | tr ' ' '\n' | grep -m 1 "@" | egrep "$CONTENT_PATTERN_MAIL_DOMAIN" | egrep -v "^$EXCLUDE_USERS")
      #// delete a carriage return CTRL + V + M
      GET_CONTENT_TO_A_1=$(grep -A60 "Subject:" /mailbot_content | egrep "$CONTENT_PATTERN_A" | egrep "$CONTENT_PATTERN_SCHEMA" | tr ' ' '\n' | grep "@" | tail -1 | egrep "$CONTENT_PATTERN_MAIL_DOMAIN" | sed -e 's///g')
      if [ "$GET_CONTENT_FROM_A_1" = "$GET_CONTENT_TO_A_1" ]
      then
         echo "[$(printf "\033[1;31mFAILED\033[0m\n")] mailaddress compare doesn't match!"
         exit 1
      fi
      ### ### ###
      GET_CONTENT_REPLY_TO_A_1=$(grep "^Reply-To:" /mailbot_content | tr ' ' '\n' | grep "@mydomain.zendesk.com" | sed 's/<//g' | sed 's/>//g')
      GET_CONTENT_REPLY_TO_A_1_MOD="${GET_CONTENT_REPLY_TO_A_1/$'\r'/}"
      #// prepare forward
      GET_CONTENT_TICKET_ID_A_1=$(grep "Ticket-Id" /mailbot_content | tr '>' '\n' | tr '<' '\n' | grep "Ticket-Id" | sed 's/Ticket-Id://g')

         #// git pull: runner-mailverteiler-management
         cd /ass.de-git/runner-mailverteiler-management
         git pull
         check_hard git pull
         #// back to the roots
         cd /ass.de-git/build-lx-mailbot

            #// EXCLUDE CHECK
            if [ -z "$GET_CONTENT_FROM_A_1" ]
            then
               #// generate send mail content
               echo "" > /mailbot_answer.txt
               echo "Hallo," >> /mailbot_answer.txt
               echo "" >> /mailbot_answer.txt
               echo "ich bin der ASS Mailbot und hatte dir versucht die Weiterleitungsregel zu aktivieren!" >> /mailbot_answer.txt
               echo "" >> /mailbot_answer.txt
               echo "Jedoch ist ein Fehler unterlaufen!" >> /mailbot_answer.txt
               echo "" >> /mailbot_answer.txt
               echo "Ich darf keine Regeln fuer Mail-Adressen der Geschaeftsleitung oder von Abteilungsleitern setzen!" >> /mailbot_answer.txt
               echo "Dieser Vorfall wurde gemeldet." >> /mailbot_answer.txt
               echo "" >> /mailbot_answer.txt
               echo "Dein Mailbot         (Version: 1.7)" >> /mailbot_answer.txt
               echo "" >> /mailbot_answer.txt
               #// send mail
               mail -s "Mailweiterleitung" "$GET_CONTENT_REPLY_TO_A_1_MOD" < /mailbot_answer.txt
               check_hard send mail - policy violation
               ### ### ###
               #// clean up
               echo "... clean up ..."
               echo "$GET_LAST_ID" > /mailbot_id
               ### ### ###
               #// EXIT
               exit 0
            fi

            #// CHECK duplicate entry
            CHECK_DUP_1=$(grep -c "$GET_CONTENT_FROM_A_1 $GET_CONTENT_TO_A_1 $GET_CONTENT_FROM_A_1" /ass.de-git/runner-mailverteiler-management/mail-verteiler_mailbot.txt)
            if [ "$CHECK_DUP_1" = "1" ]
            then
               #// generate send mail content
               echo "" > /mailbot_answer.txt
               echo "Hallo," >> /mailbot_answer.txt
               echo "" >> /mailbot_answer.txt
               echo "ich bin der ASS Mailbot und hatte dir versucht die Weiterleitungsregel zu aktualisieren!" >> /mailbot_answer.txt
               echo "" >> /mailbot_answer.txt
               echo "Jedoch ist ein Fehler unterlaufen!" >> /mailbot_answer.txt
               echo "" >> /mailbot_answer.txt
               echo "Eine Regel mit:" >> /mailbot_answer.txt
               echo "Von: $GET_CONTENT_FROM_A_1 An: $GET_CONTENT_TO_A_1 in Kopie: $GET_CONTENT_FROM_A_1" >> /mailbot_answer.txt
               echo "existiert schon!" >> /mailbot_answer.txt
               echo "" >> /mailbot_answer.txt
               echo "Dein Mailbot         (Version: 1.7)" >> /mailbot_answer.txt
               echo "" >> /mailbot_answer.txt
               #// send mail
               mail -s "Mailweiterleitung" "$GET_CONTENT_REPLY_TO_A_1_MOD" < /mailbot_answer.txt
               check_hard send mail - duplicate entry
               ### ### ###
               #// clean up
               echo "... clean up ..."
               echo "$GET_LAST_ID" > /mailbot_id
               ### ### ###
               #// EXIT
               exit 0
            fi

            #// CHECK duplicate entry / first FROM match
            CHECK_DUP_2=$(grep -c "^$GET_CONTENT_FROM_A_1" /ass.de-git/runner-mailverteiler-management/mail-verteiler_mailbot.txt)
            if [ "$CHECK_DUP_2" = "1" ]
            then
               #// generate send mail content
               echo "" > /mailbot_answer.txt
               echo "Hallo," >> /mailbot_answer.txt
               echo "" >> /mailbot_answer.txt
               echo "ich bin der ASS Mailbot und hatte dir versucht die Weiterleitungsregel zu aktualisieren!" >> /mailbot_answer.txt
               echo "" >> /mailbot_answer.txt
               echo "Jedoch ist ein Fehler unterlaufen!" >> /mailbot_answer.txt
               echo "" >> /mailbot_answer.txt
               echo "Eine aehnliche Regel mit:" >> /mailbot_answer.txt
               echo "Von: $GET_CONTENT_FROM_A_1" >> /mailbot_answer.txt
               echo "existiert schon!" >> /mailbot_answer.txt
               echo "" >> /mailbot_answer.txt
               echo "Dein Mailbot         (Version: 1.7)" >> /mailbot_answer.txt
               echo "" >> /mailbot_answer.txt
               #// send mail
               mail -s "Mailweiterleitung" "$GET_CONTENT_REPLY_TO_A_1_MOD" < /mailbot_answer.txt
               check_hard send mail - duplicate entry first from match
               ### ### ###
               #// clean up
               echo "... clean up ..."
               echo "$GET_LAST_ID" > /mailbot_id
               ### ### ###
               #// EXIT
               exit 0
            fi

            #// CHECK reverse lookup
            CHECK_DUP_3=$(grep -c "$GET_CONTENT_TO_A_1 $GET_CONTENT_FROM_A_1" /ass.de-git/runner-mailverteiler-management/mail-verteiler_mailbot.txt)
            if [ "$CHECK_DUP_3" = "1" ]
            then
               #// generate send mail content
               echo "" > /mailbot_answer.txt
               echo "Hallo," >> /mailbot_answer.txt
               echo "" >> /mailbot_answer.txt
               echo "ich bin der ASS Mailbot und hatte dir versucht die Weiterleitungsregel zu aktualisieren!" >> /mailbot_answer.txt
               echo "" >> /mailbot_answer.txt
               echo "Jedoch ist ein Fehler unterlaufen!" >> /mailbot_answer.txt
               echo "" >> /mailbot_answer.txt
               echo "Eine aehnliche Regel mit:" >> /mailbot_answer.txt
               echo "Von: $GET_CONTENT_TO_A_1 An: $GET_CONTENT_FROM_A_1" >> /mailbot_answer.txt
               echo "existiert schon!" >> /mailbot_answer.txt
               echo "" >> /mailbot_answer.txt
               echo "Dies wuerde eine Schleife erzeugen." >> /mailbot_answer.txt
               echo "" >> /mailbot_answer.txt
               echo "Dein Mailbot         (Version: 1.7)" >> /mailbot_answer.txt
               echo "" >> /mailbot_answer.txt
               #// send mail
               mail -s "Mailweiterleitung" "$GET_CONTENT_REPLY_TO_A_1_MOD" < /mailbot_answer.txt
               check_hard send mail - reverse lookup failed
               ### ### ###
               #// clean up
               echo "... clean up ..."
               echo "$GET_LAST_ID" > /mailbot_id
               ### ### ###
               #// EXIT
               exit 0
            fi

         #// merge add: runner-mailverteiler-management
         echo "" >> /ass.de-git/runner-mailverteiler-management/mail-verteiler_mailbot.txt
         echo "# TICKET: $GET_CONTENT_TICKET_ID_A_1 add forward" >> /ass.de-git/runner-mailverteiler-management/mail-verteiler_mailbot.txt
         echo "$GET_CONTENT_FROM_A_1 $GET_CONTENT_TO_A_1 $GET_CONTENT_FROM_A_1" >> /ass.de-git/runner-mailverteiler-management/mail-verteiler_mailbot.txt
         echo "" >> /ass.de-git/runner-mailverteiler-management/mail-verteiler_mailbot.txt

         #// git push: runner-mailverteiler-management
         cd /ass.de-git/runner-mailverteiler-management
         git add -A
         git commit -m "Mailbot TICKET: $GET_CONTENT_TICKET_ID_A_1 add forward"
         git push origin master
         check_hard git push
         #// back to the roots
         cd /ass.de-git/build-lx-mailbot

         #// generate send mail content
         echo "" > /mailbot_answer.txt
         echo "Hallo," >> /mailbot_answer.txt
         echo "" >> /mailbot_answer.txt
         echo "ich bin der ASS Mailbot und habe dir die Weiterleitungsregel aktiviert!" >> /mailbot_answer.txt
         echo "Von: $GET_CONTENT_FROM_A_1 An: $GET_CONTENT_TO_A_1 in Kopie: $GET_CONTENT_FROM_A_1" >> /mailbot_answer.txt
         echo "" >> /mailbot_answer.txt
         echo "Dein Mailbot         (Version: 1.7)" >> /mailbot_answer.txt
         echo "" >> /mailbot_answer.txt

         #// send mail
         mail -s "Mailweiterleitung" "$GET_CONTENT_REPLY_TO_A_1_MOD" < /mailbot_answer.txt
         check_hard send mail - add forward

         ### ### ###
         #// clean up
         echo "... clean up ..."
         echo "$GET_LAST_ID" > /mailbot_id
         ### ### ###

      ### ### ###
   else
      echo "[$(printf "\033[1;31mFAILED\033[0m\n")] Format doesn't match!"
      exit 1
   fi
}

#// FUNCTION: mailbot forward deactivation
deactivation() {
   echo "... deactivation ..."
   #// check format
   CHECK_CONTENT_D_2=$(grep -A60 "Subject:" /mailbot_content | egrep "$CONTENT_PATTERN_D" | egrep "$CONTENT_PATTERN_SCHEMA" | tr ' ' '\n' | wc -l)
   if [ "$CHECK_CONTENT_D_2" = "5" ]
   then
      #// check format
      GET_CONTENT_FROM_D_1=$(grep -A60 "Subject:" /mailbot_content | egrep "$CONTENT_PATTERN_D" | egrep "$CONTENT_PATTERN_SCHEMA" | tr ' ' '\n' | grep -m 1 "@" | egrep "$CONTENT_PATTERN_MAIL_DOMAIN" | egrep -v "^$EXCLUDE_USERS")
      #// delete a carriage return CTRL + V + M
      GET_CONTENT_TO_D_1=$(grep -A60 "Subject:" /mailbot_content | egrep "$CONTENT_PATTERN_D" | egrep "$CONTENT_PATTERN_SCHEMA" | tr ' ' '\n' | grep "@" | tail -1 | egrep "$CONTENT_PATTERN_MAIL_DOMAIN" | sed -e 's///g')
      if [ "$GET_CONTENT_FROM_D_1" = "$GET_CONTENT_TO_D_1" ]
      then
         echo "[$(printf "\033[1;31mFAILED\033[0m\n")] mailaddress compare doesn't match!"
         exit 1
      fi
      ### ### ###
      GET_CONTENT_REPLY_TO_D_1=$(grep "^Reply-To:" /mailbot_content | tr ' ' '\n' | grep "@mydomain.zendesk.com" | sed 's/<//g' | sed 's/>//g')
      GET_CONTENT_REPLY_TO_D_1_MOD="${GET_CONTENT_REPLY_TO_D_1/$'\r'/}"
      #// prepare forward
      GET_CONTENT_TICKET_ID_D_1=$(grep "Ticket-Id" /mailbot_content | tr '>' '\n' | tr '<' '\n' | grep "Ticket-Id" | sed 's/Ticket-Id://g')

         #// git pull: runner-mailverteiler-management
         cd /ass.de-git/runner-mailverteiler-management
         git pull
         check_hard git pull
         #// back to the roots
         cd /ass.de-git/build-lx-mailbot

         #// merge delete: runner-mailverteiler-management
         sed -i "s/$GET_CONTENT_FROM_D_1 $GET_CONTENT_TO_D_1 $GET_CONTENT_FROM_D_1/# TICKET: $GET_CONTENT_TICKET_ID_D_1 delete forward/g" /ass.de-git/runner-mailverteiler-management/mail-verteiler_mailbot.txt

         #// git push: runner-mailverteiler-management
         cd /ass.de-git/runner-mailverteiler-management
         git add -A
         git commit -m "Mailbot TICKET: $GET_CONTENT_TICKET_ID_D_1 delete forward"
         git push origin master
         check_hard git push
         #// back to the roots
         cd /ass.de-git/build-lx-mailbot

         #// generate send mail content
         echo "" > /mailbot_answer.txt
         echo "Hallo," >> /mailbot_answer.txt
         echo "" >> /mailbot_answer.txt
         echo "ich bin der ASS Mailbot und habe dir die Weiterleitungsregel deaktiviert!" >> /mailbot_answer.txt
         echo "Von: $GET_CONTENT_FROM_D_1 An: $GET_CONTENT_TO_D_1 in Kopie: $GET_CONTENT_FROM_D_1" >> /mailbot_answer.txt
         echo "" >> /mailbot_answer.txt
         echo "Dein Mailbot         (Version: 1.7)" >> /mailbot_answer.txt
         echo "" >> /mailbot_answer.txt

         #// send mail
         mail -s "Mailweiterleitung" "$GET_CONTENT_REPLY_TO_D_1_MOD" < /mailbot_answer.txt
         check_hard send mail - delete forward

         ### ### ###
         #// clean up
         echo "... clean up ..."
         echo "$GET_LAST_ID" > /mailbot_id
         ### ### ###

      ### ### ###
   else
      echo "[$(printf "\033[1;31mFAILED\033[0m\n")] Format doesn't match!"
      exit 1
   fi
}

### RUN ###

#set_lx_hosts_config
#check_hard setting: new hosts config inside lx-zone

#install_package sudo less wget curl
#check_hard install: sudo less wget curl

mailbot
check_hard run mailbot stage 1

if [ "$STAGE" = "ACTIVATION" ]
then
   activation
   check_hard run mailbot stage 2
   exit 0
fi

if [ "$STAGE" = "DEACTIVATION" ]
then
   deactivation
   check_hard run mailbot stage 2
   exit 0
fi

echo ""
echo "### ### ### ### ### ### ### ### ### ### ### ### ### ###"
echo "#                                                     #"
echo "  Container IPv4:     '$GET_IPv4'                      "
echo "  Container IPv6:     '$GET_IPv6'                      "
echo "#                                                     #"
echo "### ### ### ### ### ### ### ### ### ### ### ### ### ###"
echo ""

### ### ### // ASS ### ### ###
exit 0
# EOF
