#!/bin/bash



# kaboom    -    automatic pentest
# Copyright © 2019 Leviathan36 

# kaboom is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# kaboom is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with kaboom.  If not, see <http://www.gnu.org/licenses/>.


##############################################
###             VARIABLES BRUTEFORCE       ###  
##############################################

#KABOOM_PATH=''     # THE KABOOM DIRECOTRY PATH COULD BE SET HERE INSTEAD OF IN THE BASHRC FILE

if [[ "$KABOOM_PATH" == '' ]]; then 
    KABOOM_PATH='.'
fi

# USER WORDLISTS
USERLIST_HYDRA_SSH="$KABOOM_PATH/user_wordlist_short.txt"
USERLIST_HYDRA_POP3="$KABOOM_PATH/user_wordlist_short.txt"
USERLIST_HYDRA_IMAP="$KABOOM_PATH/user_wordlist_short.txt"
USERLIST_HYDRA_RDP="$KABOOM_PATH/user_wordlist_short.txt"
USERLIST_HYDRA_SMB="$KABOOM_PATH/user_wordlist_short.txt"
USERLIST_HYDRA_MYSQL="$KABOOM_PATH/user_wordlist_short.txt"
USERLIST_HYDRA_FTP="$KABOOM_PATH/user_wordlist_short.txt"
USERLIST_HYDRA_TELNET="$KABOOM_PATH/user_wordlist_short.txt"
USERLIST_HYDRA_POSTGRESQL="$KABOOM_PATH/user_wordlist_short.txt"
USERLIST_HYDRA_MSSQL="$KABOOM_PATH/user_wordlist_short.txt"

# PASSWORD WORDLISTS
PASSLIST_HYDRA="$KABOOM_PATH/fasttrack.txt"
PASSLIST_HYDRA_SSH="$PASSLIST_HYDRA"
PASSLIST_HYDRA_POP3="$PASSLIST_HYDRA"
PASSLIST_HYDRA_IMAP="$PASSLIST_HYDRA"
PASSLIST_HYDRA_RDP="$PASSLIST_HYDRA"
PASSLIST_HYDRA_SMB="$PASSLIST_HYDRA"
PASSLIST_HYDRA_MYSQL="$PASSLIST_HYDRA"
PASSLIST_HYDRA_FTP="$PASSLIST_HYDRA"
PASSLIST_HYDRA_TELNET="$PASSLIST_HYDRA"
PASSLIST_HYDRA_VNC="$PASSLIST_HYDRA"
PASSLIST_HYDRA_POSTGRESQL="$PASSLIST_HYDRA"
PASSLIST_HYDRA_MSSQL="$PASSLIST_HYDRA"
PASSLIST_HYDRA_SNMP="$PASSLIST_HYDRA"

# DIRB WORDLISTS
HTTP_WORDLIST="$KABOOM_PATH/custom_url_wordlist.txt"
HTTP_EXTENSIONS_FILE="$KABOOM_PATH/custom_extensions_common.txt"

# METASPLOIT SCAN SCRIPT
METASPLOIT_SCAN_SCRIPT='./metasploit_scan_script'

# NMAP FILES
SCRIPT_SYN='script-syn'
UDP='udp'
SYN='syn'

# HYDRA THREADS (concurrent connections per dictionary attack)
HYDRA_THREADS=4

# PARALLEL TARGET SCANS (how many hosts to scan concurrently; 1 = sequential, default)
PARALLEL_JOBS=1

##############################################
##############################################

##############################################
###           OPTIONAL CONFIG FILE         ###
##############################################

# Any variable set above (wordlists, HYDRA_THREADS, PARALLEL_JOBS,
# METASPLOIT_SCAN_SCRIPT, ...) can be overridden by placing a
# kaboom.conf file (plain bash variable assignments) in $KABOOM_PATH.
KABOOM_CONFIG="$KABOOM_PATH/kaboom.conf"
if [[ -f "$KABOOM_CONFIG" ]]; then
    source "$KABOOM_CONFIG"
fi

##############################################
##############################################



########################################################
############            FUNCTIONS          #############
########################################################


print_help () {
    echo 'Usage:'
    echo '  Interactive mode:'
    echo '      kaboom [ENTER]  ...and the script does the rest'
    echo
    echo '  NON-interactive mode:'
    echo '      kaboom -t <target_ip> -f <report_path> [-p one_or_more_phases]'
    echo 
    echo '      phases:'
    echo '          - i == information gathering'
    echo '          - v == vulnerability assessment'
    echo '          - d == dictionary attack against open services'
    echo '          - r == generate consolidated HTML report'
    echo
    echo '      example: iv == information gathering + vulnerability assessment'
    echo '      dafult: ALL (ivdr)'
    echo
}

##                   ## 
### PRINT FUNCTIONS ###
##                   ##

print_start_end () {
    printf "\n\033[37;41;1m[*******************************************************]\033[0m\n"
    printf "\033[37;41;1m[***]$1[***]\033[0m\n"
    printf "\033[37;41;1m[*******************************************************]\033[0m\n"
}

#
#  name: print_status
#  @param: iteration ; actual target ; progress
#  @return
#  
print_status () {
    echo
    echo '----------------------------------'
    echo '----------------------------------'
    echo "ITAREATION:   $1"
    echo "TARGET:   $2"
    printf 'PROGRESS: ['
    for i in {1..20}; do
        if [[ "$i" -lt "$3" ]]; then
            printf '='
        elif [[ "$i" == "$3" ]]; then
            printf '>'
        else 
            printf ' '
        fi
    done
    printf "]\n"
    echo '----------------------------------'
    echo
}
    

print_std () {
    printf "\t\033[34;1m[*]$1\033[0m\n"
}

print_phase () {
    printf "\n\033[01;33m[PHASE:]$1\033[0m\n"
}

print_succ () {
    printf "\n\t\033[32;1m[+]$1\033[0m\n"
}

print_failure () {
    printf "\n\t\033[01;31m[-]$1\033[0m\n"
}

failure () {
    print_failure "$1"
    exit 1
}

###                 ###

##                        ##
### DEPENDENCY CHECKING  ###
##                        ##

#
#  name: check_dependencies
#  @param: none
#  @return: warns (non-fatal) about any missing external tool kaboom relies on
#
check_dependencies () {
    local REQUIRED_TOOLS=(nmap dirb nikto hydra searchsploit msfconsole xmllint gobuster whatweb sslscan enum4linux)
    local MISSING=()

    for TOOL in "${REQUIRED_TOOLS[@]}"; do
        command -v "$TOOL" > /dev/null 2>&1 || MISSING+=("$TOOL")
    done

    if [[ "${#MISSING[@]}" -gt 0 ]]; then
        print_failure "missing tools (their scans will silently be skipped): ${MISSING[*]}"
    fi
}

###                 ###


sanitize_input () {
    
    if [[ ! "$#" == 0 ]]; then      # NO-interactive
    
        while [[ ! "$#" == 0 ]]; do
            case "$1" in
                -h | --help ) print_help; exit 0;;
                -t | --target ) HOSTS="$2"; shift 2;;
                -f | --file ) ROOT_PATH="$2"; shift 2;;
                -p | --phase ) PHASE="$2"; shift 2;;
                * ) print_failure 'INVALID PARAMETER!'; exit 10;;
            esac
        done
    
    else                            # interactive
        
        # HOST
        printf "Insert hosts (example 192.168.1.1-5):\n>> "
        read HOSTS
        
        # PATH
        printf "Insert path where to save results (without final /):\n>> " 
        read ROOT_PATH
        
        # PHASE
        printf "choice the phases to perform [i=IG, v=VA, d=dictionary, r=report]:\n>> "
        read PHASE
        while [[ ! "$PHASE" =~ ['ivdr'] ]]; do
            echo 'INVALID PARAMETER'
            printf "choice the phases to perform [i=IG, v=VA, d=dictionary, r=report]:\n>> "
            read PHASE
        done
        
        # SHUTDOWN
        printf "Shutdown pc at the end of script [YES/NO] (default NO):\n>> "
        read SHUTDOWN
    fi
        
    # PARAMETERS SANITIZE
    
    if [[ "$HOSTS" =~ ['qwertyuiopasdfghjklzxcvbnm,:;#@[]/%|'] ]]; then 
        echo 'TARGET IP CONTAINS INVALID CHARACTERS [not use CIDR notation]'
        exit 1
    fi
    
    if [[ ! -d "$ROOT_PATH" ]]; then 
        echo "$ROOT_PATH: DIRECTORY NOT FOUND"
        exit 1
    fi

    # create hosts range
    LOWER_HOST=$(cut -f4 -d '.' <<< "$HOSTS" | cut -f1 -d '-')
    UPPER_HOST=$(cut -f4 -d '.' <<< "$HOSTS" | cut -f2 -d '-')
    ROOT_HOST=$(cut -f1,2,3 -d '.' <<< "$HOSTS")
}

##                   ##
###   XML PARSER    ###
##                   ##

#  
#  name: tcp_service_on 
#  @param: state of port={open, filtered} ; port name={http, ssh, ...} ; ssl={1 == YES, 0 == NO}
#  @return: 0 = {port found} ; 10 {port not found}
#  
tcp_service_on () {
    if [[ "$3" == '0' ]]; then 
        xmllint --xpath "//port[state[@state='$1'] and service[@name='$2']]" "$FILE_PATH/IG/NMAP/$SCRIPT_SYN.xml" &> /dev/null
    elif [[ "$3" == '1' ]]; then 
        xmllint --xpath "//port[state[@state='$1'] and service[@name='$2' and @tunnel='ssl']]" "$FILE_PATH/IG/NMAP/$SCRIPT_SYN.xml" &> /dev/null
    else 
        return 1    #ERROR
    fi
}

#  
#  name: udp_service_on 
#  @param: port name={rpcbind, mdns, ...}
#  @return: 0 = {port found} ; 10 {port not found}
# 
udp_service_on () {
    xmllint --xpath "//port[state[@state='open|filtered'] and service[@name='$1']]" "$FILE_PATH/IG/NMAP/$UDP.xml" &> /dev/null
}

#  
#  name: print_portid
#  @param: state of port={open, filtered} ; port name={http, ssh, ...} ; ssl={1 == YES, 0 == NO}
#  @return: portid
#
print_portid () {
    if [[ "$3" == '0' ]]; then
        xmllint --xpath "//port[state[@state='$1'] and service[@name='$2']]/@portid" "$FILE_PATH/IG/NMAP/$SCRIPT_SYN.xml" | cut -c 2- | tr " " "\n" | cut -f2 -d'"'
    elif [[ "$3" == '1' ]]; then
        xmllint --xpath "//port[state[@state='$1'] and service[@name='$2' and @tunnel='ssl']]/@portid" "$FILE_PATH/IG/NMAP/$SCRIPT_SYN.xml" | cut -c 2- | tr " " "\n" | cut -f2 -d'"'
    else
        return 1    #ERROR
    fi
}

#
#  name: print_portid_udp
#  @param: port name={snmp, ...}
#  @return: portid
#
print_portid_udp () {
    xmllint --xpath "//port[state[@state='open|filtered'] and service[@name='$1']]/@portid" "$FILE_PATH/IG/NMAP/$UDP.xml" | cut -c 2- | tr " " "\n" | cut -f2 -d'"'
}

###                 ###

##                    ##
###   REPORT (HTML)  ###
##                    ##

#
#  name: generate_report
#  @param: none (uses global $HOST, $FILE_PATH, $SYN, $UDP)
#  @return:
#
generate_report () {
    mkdir -p "$FILE_PATH/REPORT"
    local REPORT_FILE="$FILE_PATH/REPORT/index.html"

    {
        echo "<html><head><title>kaboom report - $HOST</title>"
        echo '<style>body{font-family:monospace;margin:2em;background:#111;color:#eee;} h1,h2{color:#7CFC00;} pre{background:#000;padding:1em;overflow-x:auto;border:1px solid #333;white-space:pre-wrap;}</style>'
        echo '</head><body>'
        echo "<h1>kaboom report - $HOST</h1>"
        echo "<p>Generated: $(date)</p>"

        echo '<h2>Open TCP ports (nmap SYN scan)</h2><pre>'
        [[ -f "$FILE_PATH/IG/NMAP/$SYN.nmap" ]] && sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "$FILE_PATH/IG/NMAP/$SYN.nmap"
        echo '</pre>'

        echo '<h2>Open UDP ports (nmap UDP scan)</h2><pre>'
        [[ -f "$FILE_PATH/IG/NMAP/$UDP.nmap" ]] && sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "$FILE_PATH/IG/NMAP/$UDP.nmap"
        echo '</pre>'

        echo '<h2>Vulnerable CVEs found</h2><pre>'
        [[ -f "$FILE_PATH/IG/NMAP/CVE.txt" ]] && grep 'CVE-' "$FILE_PATH/IG/NMAP/CVE.txt"
        echo '</pre>'

        echo '<h2>Known exploits (searchsploit)</h2><pre>'
        [[ -f "$FILE_PATH/VA/KNOWN_EXPLOITS/exploit-db.txt" ]] && sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "$FILE_PATH/VA/KNOWN_EXPLOITS/exploit-db.txt"
        echo '</pre>'

        echo '<h2>Cracked credentials (dictionary attacks)</h2><pre>'
        if [[ -d "$FILE_PATH/DA/PASSWORD" ]]; then
            for CREDFILE in "$FILE_PATH"/DA/PASSWORD/cred_*; do
                [[ -f "$CREDFILE" ]] || continue
                grep 'host:' "$CREDFILE" 2> /dev/null
            done
        fi
        echo '</pre>'

        echo '</body></html>'
    } > "$REPORT_FILE"

    print_succ "report generated: $REPORT_FILE"
}

###                 ###

######################################
######################################



######################################
###             CODE               ###
######################################

# sanitize input
sanitize_input "$@"

# warn (non-fatally) about any missing tool before scanning starts
check_dependencies

# start script
print_start_end "START SCRIPT AT `date`"

for i in $(seq $LOWER_HOST 1 $UPPER_HOST); do

    # throttle to PARALLEL_JOBS concurrent host scans (default 1 == sequential, same as before)
    while [[ "$(jobs -rp | wc -l)" -ge "$PARALLEL_JOBS" ]]; do
        wait -n
    done

  ( # each host scan runs in its own subshell so PARALLEL_JOBS>1 can run them concurrently
    # without host runs stomping on each other's HOST/FILE_PATH globals

    # HOST
    HOST="$ROOT_HOST.$i"

    # print status (index derived from $i, since concurrent hosts can finish out of order)
    ITERATION=$(( (10#$i - 10#$LOWER_HOST) + 1 ))
    TOTAL_ITERATION=$(((UPPER_HOST-LOWER_HOST)+1))
    PROGRESS=$(((ITERATION*20)/TOTAL_ITERATION))
    print_status "$ITERATION" "$HOST" "$PROGRESS"

    # create new directory
    mkdir -p "$ROOT_PATH/$HOST"
    FILE_PATH="$ROOT_PATH/$HOST"

    #** start information gathering (IG) **#

    if [[ "$PHASE" =~ 'i' || "$PHASE" == '' ]]; then 
        print_phase 'starting IG...'
        sleep 2
        
        # create new directories for IG results
        mkdir -p "$FILE_PATH/IG"
        mkdir -p "$FILE_PATH/IG/NMAP"
        
        ### NMAP ###
        print_succ 'nmap is scanning...'
        
        # syn-scan
        print_std 'start syn-scan with syn-probe...'
        nmap -vvv -oA "$FILE_PATH/IG/NMAP/$SCRIPT_SYN" -PE -PS80,443,22,25,110,445 -PU -PP -PA80,443,22,25,110,445 -sS -p- -sV --allports -O --fuzzy --script "(default or auth or vuln or exploit) and not http-enum" "$HOST"   | grep 'Host seems down' > /dev/null && { print_failure 'Host down' ; rm -fR "$FILE_PATH"; exit 0; }     #|| failure "NMAP ERROR (SYN-SCAN); exit with code $?"

        # if nmap didn't produce its XML output (permissions, bad interface, crash, ...),
        # every later phase parses that file blindly and would silently "find" nothing;
        # bail out for this host instead of pretending the scan succeeded.
        if [[ ! -s "$FILE_PATH/IG/NMAP/$SCRIPT_SYN.xml" ]]; then
            print_failure "nmap SYN-scan produced no output for $HOST (check permissions/interface); skipping host"
            exit 0
        fi

        # create syn report
        if [[ -f "$FILE_PATH/IG/NMAP/$SCRIPT_SYN.nmap" ]]; then
            grep -v '|' "$FILE_PATH/IG/NMAP/$SCRIPT_SYN.nmap" > "$FILE_PATH/IG/NMAP/$SYN.nmap"
        fi
        
        # udp scan
        print_std 'start udp-scan with udp-probe...'
        nmap -vvv -oA "$FILE_PATH/IG/NMAP/$UDP" -PE -PS80,443,22,25,110,445 -PU -PP -PA80,443,22,25,110,445 -sU --top-ports 200 -sV --allports "$HOST" > /dev/null || failure "NMAP ERROR (UDP-SCAN); exit with code $?"
        
        # golismero report
        #golismero report -i "$file_path/IG/NMAP/script.xml" -o "$file_path/IG/NMAP/nmap_report.html"
        
    #--------------------------------------------#  
        #### UNICORNSCAN ###
        #print_succ 'unicornscan is scanning...'
        
        ## unicornscan tcp scan
        #print_std 'starting TCP scan...'
        #unicornscan -E -L 10 -R 2 -l "$FILE_PATH/IG/unicorn-tcp.txt" -i "$NIC" -r 30 -vvvvv "$HOST":p > /dev/null
            #### p=ports between [1,1024]
            #### r X=max X packet per second
            
        ## unicornscan udp scan
        #print_std 'starting UDP scan...'
        #unicornscan -E -L 10 -R 2 -l "$FILE_PATH/IG/unicorn-udp.txt" -i "$NIC" -r 30 -mU -vvvvv "$HOST":p > /dev/null
    #--------------------------------------------#  
        
        ### METASPLOIT ###
        print_succ 'metasploit is scanning...'
        
        # start postgresql server
        service postgresql start
        
        # 
        msfconsole -q -o "$FILE_PATH/IG/metasploit_scan.txt" -x "setg rhosts $HOST ; resource $METASPLOIT_SCAN_SCRIPT ; exit -y"

        
    fi

    #** start vulnerability assessment (VA) **#

    if [[ "$PHASE" =~ 'v' || "$PHASE" == '' ]]; then 
        
        print_phase 'starting VA...'
        
        # create new directory for this phase
        mkdir -p "$FILE_PATH/VA"

        # parse nmap output in search of CVE
        xmllint --xpath "//table[elem[text()='VULNERABLE' and @key='state']]/@key" "$FILE_PATH/IG/NMAP/$SCRIPT_SYN.xml" 2> /dev/null | tr " " "\n" | cut -f2 -s -d'"' | awk -F "CVE-" '{printf "search cve:" ; print $2}' > "$FILE_PATH/IG/NMAP/CVE.txt"
        xmllint --xpath "//table[elem[text()='VULNERABLE' and @key='state']]/@key" "$FILE_PATH/IG/NMAP/$UDP.xml" 2> /dev/null | tr " " "\n" | cut -f2 -s -d'"' | awk -F "CVE-" '{printf "search cve:" ; print $2}' >> "$FILE_PATH/IG/NMAP/CVE.txt"
        
        # create new dir for exploits
        mkdir -p "$FILE_PATH/VA/KNOWN_EXPLOITS"
        # remove old file
        rm -f "$FILE_PATH/VA/KNOWN_EXPLOITS/NO_cve_found.txt"
        
        # if the file contains at least one CVE, the research will start
        if grep 'CVE-' "$FILE_PATH/IG/NMAP/CVE.txt"; then       
            
            print_succ 'starting Metasploit research...'
            
            msfconsole -q -o "$FILE_PATH/VA/KNOWN_EXPLOITS/meta_module.txt" -x "db_rebuild_cache ; resource $FILE_PATH/IG/NMAP/CVE.txt ; exit -y" 
            
            # searchsploit
            print_succ 'starting searchsploit...'
            
            searchsploit --www --nmap "$FILE_PATH/IG/NMAP/$SCRIPT_SYN.xml" > "$FILE_PATH/VA/KNOWN_EXPLOITS/exploit-db.txt"
            searchsploit --www --nmap "$FILE_PATH/IG/NMAP/$UDP.xml" >> "$FILE_PATH/VA/KNOWN_EXPLOITS/exploit-db.txt"

        else
            print_failure 'no exploits found!'
            touch "$FILE_PATH/VA/KNOWN_EXPLOITS/NO_cve_found.txt"
        fi
        
        
        ## WIFIBANG
        ## tail -n +15 "$file_path/VA/META_MODULE/$i" | awk -F"   " '{print $2}' | nl

        #http
        tcp_service_on 'open' 'http' '0' && {
            print_succ 'starting nikto...';
            for PORT in $(print_portid 'open' 'http' '0'); do
                print_std "Nikto port: $PORT"
                nikto -Display PV -nolookup -ask no -Format htm -host $HOST:$PORT -output "$FILE_PATH/VA/nikto_$PORT.html" -Plugins "ms10_070;report_html;embedded;cookies;put_del_test;outdated;drupal(0:0);clientaccesspolicy;msgs;httpoptions;negotiate;parked;favicon;apache_expect_xss;headers" -Tuning 4890bcde > /dev/null
            done;

            print_succ 'starting dirb...';
            for PORT in $(print_portid 'open' 'http' '0'); do
                print_std "Dirb port: $PORT"
                dirb "http://$HOST:$PORT/" "$HTTP_WORDLIST" -r -l -o "$FILE_PATH/VA/dirb_$PORT.txt" -x "$HTTP_EXTENSIONS_FILE" -z 200 > /dev/null
            done;

            print_succ 'starting gobuster...';
            for PORT in $(print_portid 'open' 'http' '0'); do
                print_std "Gobuster port: $PORT"
                gobuster dir -u "http://$HOST:$PORT/" -w "$HTTP_WORDLIST" -o "$FILE_PATH/VA/gobuster_$PORT.txt" -q > /dev/null
            done;

            print_succ 'starting whatweb...';
            for PORT in $(print_portid 'open' 'http' '0'); do
                print_std "Whatweb port: $PORT"
                whatweb -a 3 "http://$HOST:$PORT/" --log-brief "$FILE_PATH/VA/whatweb_$PORT.txt" > /dev/null
            done;
        }
            
            #Dirb takes approximaly one hour to finish the wordlist with the following setting.
            #It doesn't search recursively.

        #https
        tcp_service_on 'open' 'https' '0' && {
            # execute nikto and dirb for https protocol
            print_succ 'starting nikto (https)...';
            for PORT in $(print_portid 'open' 'https' '0'); do
                print_std "Nikto port: $PORT"
                nikto -ssl -port $PORT -Display PV -nolookup -ask no -Format htm -host $HOST -output "$FILE_PATH/VA/nikto_https_$PORT.html" -Plugins "ms10_070;report_html;embedded;cookies;put_del_test;outdated;drupal(0:0);clientaccesspolicy;msgs;httpoptions;negotiate;parked;favicon;apache_expect_xss;ssl;headers" -Tuning 4890bcde > /dev/null
            done;
            
            print_succ 'starting dirb (https)...';
            for PORT in $(print_portid 'open' 'https' '0'); do
                print_std "Dirb port: $PORT"
                dirb "https://$HOST:$PORT/" "$HTTP_WORDLIST" -r -l -o "$FILE_PATH/VA/dirb_https_$PORT.txt" -x "$HTTP_EXTENSIONS_FILE" -z 200 > /dev/null
            done;

            print_succ 'starting gobuster (https)...';
            for PORT in $(print_portid 'open' 'https' '0'); do
                print_std "Gobuster port: $PORT"
                gobuster dir -u "https://$HOST:$PORT/" -w "$HTTP_WORDLIST" -o "$FILE_PATH/VA/gobuster_https_$PORT.txt" -k -q > /dev/null
            done;

            print_succ 'starting whatweb (https)...';
            for PORT in $(print_portid 'open' 'https' '0'); do
                print_std "Whatweb port: $PORT"
                whatweb -a 3 "https://$HOST:$PORT/" --log-brief "$FILE_PATH/VA/whatweb_https_$PORT.txt" > /dev/null
            done;

            print_succ 'starting sslscan (https)...';
            for PORT in $(print_portid 'open' 'https' '0'); do
                print_std "Sslscan port: $PORT"
                sslscan --no-colour "$HOST:$PORT" > "$FILE_PATH/VA/sslscan_https_$PORT.txt"
            done;
        }

        #ssl/http
        tcp_service_on 'open' 'http' '1' && {
            # execute nikto and dirb for ssl/http protocol
            print_succ 'starting nikto (ssl/http)...';
            for PORT in $(print_portid 'open' 'http' '1'); do
                print_std "Nikto port: $PORT"
                nikto -ssl -port $PORT -Display PV -nolookup -ask no -Format htm -host $HOST -output "$FILE_PATH/VA/nikto_https_$PORT.html" -Plugins "ms10_070;report_html;embedded;cookies;put_del_test;outdated;drupal(0:0);clientaccesspolicy;msgs;httpoptions;negotiate;parked;favicon;apache_expect_xss;ssl;headers" -Tuning 4890bcde > /dev/null
            done;
            
            print_succ 'starting dirb (ssl/http)...';
            for PORT in $(print_portid 'open' 'http' '1'); do
                print_std "Dirb port: $PORT"
                dirb "https://$HOST:$PORT/" "$HTTP_WORDLIST" -r -l -o "$FILE_PATH/VA/dirb_https_$PORT.txt" -x "$HTTP_EXTENSIONS_FILE" -z 200 > /dev/null
            done;

            print_succ 'starting gobuster (ssl/http)...';
            for PORT in $(print_portid 'open' 'http' '1'); do
                print_std "Gobuster port: $PORT"
                gobuster dir -u "https://$HOST:$PORT/" -w "$HTTP_WORDLIST" -o "$FILE_PATH/VA/gobuster_ssl_http_$PORT.txt" -k -q > /dev/null
            done;

            print_succ 'starting whatweb (ssl/http)...';
            for PORT in $(print_portid 'open' 'http' '1'); do
                print_std "Whatweb port: $PORT"
                whatweb -a 3 "https://$HOST:$PORT/" --log-brief "$FILE_PATH/VA/whatweb_ssl_http_$PORT.txt" > /dev/null
            done;

            print_succ 'starting sslscan (ssl/http)...';
            for PORT in $(print_portid 'open' 'http' '1'); do
                print_std "Sslscan port: $PORT"
                sslscan --no-colour "$HOST:$PORT" > "$FILE_PATH/VA/sslscan_ssl_http_$PORT.txt"
            done;
        }

        #smb enumeration
        tcp_service_on 'open' 'microsoft-ds' '0' && {
            print_succ 'starting enum4linux...';
            enum4linux -a "$HOST" > "$FILE_PATH/VA/enum4linux.txt"
        }

    fi

    #####################################

    #** start dictionary attacks (DA) **#

    if [[ "$PHASE" =~ 'd' || "$PHASE" == '' ]]; then

        print_phase 'starting Dictionary Attacks...'
        
        # create the new directories for this phase
        mkdir -p "$FILE_PATH/DA/PASSWORD"
        mkdir -p "$FILE_PATH/DA/EVIDENCE"
        
        #ssh
        tcp_service_on 'open' 'ssh' '0' && {
            print_succ 'starting dictionary attack against SSH service...';
            for PORT in $(print_portid 'open' 'ssh' '0'); do
            hydra -s $PORT -v -V -o "$FILE_PATH/DA/PASSWORD/cred_ssh" -L $USERLIST_HYDRA_SSH -P $PASSLIST_HYDRA_SSH -t $HYDRA_THREADS $HOST ssh &> "$FILE_PATH/DA/EVIDENCE/ssh_attack"
            print_std "$(grep 'host:' "$FILE_PATH/DA/PASSWORD/cred_ssh" || echo 'PASSWORD NOT FOUND')"
            done;
        }
        
        #pop3
        tcp_service_on 'open' 'pop3' '0' && {
            print_succ 'starting dictionary attack against POP3 (clear pass) service...';
            for PORT in $(print_portid 'open' 'pop3' '0'); do
            hydra -s $PORT -v -V -o "$FILE_PATH/DA/PASSWORD/cred_pop3" -L $USERLIST_HYDRA_POP3 -P $PASSLIST_HYDRA_POP3 -t $HYDRA_THREADS $HOST pop3 &> "$FILE_PATH/DA/EVIDENCE/pop3_attack"
            print_std "$(grep 'host:' "$FILE_PATH/DA/PASSWORD/cred_pop3" || echo 'PASSWORD NOT FOUND')"
            done;
        }
        
        #pop3s
        tcp_service_on 'open' 'pop3s' '0' && {
            print_succ 'starting dictionary attack against POP3S (plain pass over ssl connection) service...';
            for PORT in $(print_portid 'open' 'pop3s' '0'); do
            hydra -S -s $PORT -v -V -o "$FILE_PATH/DA/PASSWORD/cred_pop3s" -L $USERLIST_HYDRA_POP3 -P $PASSLIST_HYDRA_POP3 -t $HYDRA_THREADS $HOST pop3s &> "$FILE_PATH/DA/EVIDENCE/pop3s_attack"
            print_std "$(grep 'host:' "$FILE_PATH/DA/PASSWORD/cred_pop3s" || echo 'PASSWORD NOT FOUND')"
            done;
        }
        
        #ssl/pop3
        tcp_service_on 'open' 'pop3' '1' && {
            print_succ 'starting dictionary attack against SSL/POP3 (plain pass over ssl connection) service...';
            for PORT in $(print_portid 'open' 'pop3' '1'); do
            hydra -S -s $PORT -v -V -o "$FILE_PATH/DA/PASSWORD/cred_ssl_pop3" -L $USERLIST_HYDRA_POP3 -P $PASSLIST_HYDRA_POP3 -t $HYDRA_THREADS $HOST pop3 &> "$FILE_PATH/DA/EVIDENCE/ssl_pop3_attack"
            print_std "$(grep 'host:' "$FILE_PATH/DA/PASSWORD/cred_ssl_pop3" || echo 'PASSWORD NOT FOUND')"
            done;
        }
        
        #imap
        tcp_service_on 'open' 'imap' '0' && {
            print_succ 'starting dictionary attack against IMAP (clear pass) service...';
            for PORT in $(print_portid 'open' 'imap' '0'); do
            hydra -s $PORT -v -V -o "$FILE_PATH/DA/PASSWORD/cred_imap" -L $USERLIST_HYDRA_IMAP -P $PASSLIST_HYDRA_IMAP -t $HYDRA_THREADS $HOST imap &> "$FILE_PATH/DA/EVIDENCE/imap_attack"
            print_std "$(grep 'host:' "$FILE_PATH/DA/PASSWORD/cred_imap" || echo 'PASSWORD NOT FOUND')"
            done;
        }
        
        #imaps
        tcp_service_on 'open' 'imaps' '0' && {
            print_succ 'starting dictionary attack against IMAPS (plain pass over ssl connection) service...';
            for PORT in $(print_portid 'open' 'imaps' '0'); do
            hydra -S -s $PORT -v -V -o "$FILE_PATH/DA/PASSWORD/cred_imaps" -L $USERLIST_HYDRA_IMAP -P $PASSLIST_HYDRA_IMAP -t $HYDRA_THREADS $HOST imaps &> "$FILE_PATH/DA/EVIDENCE/imaps_attack"
            print_std "$(grep 'host:' "$FILE_PATH/DA/PASSWORD/cred_imaps" || echo 'PASSWORD NOT FOUND')"
            done;
        }
        
        #rdp
        tcp_service_on 'open' 'ms-wbt-server' '0' && {
            print_succ 'starting dictionary attack against RDP service (no domain)...';
            for PORT in $(print_portid 'open' 'ms-wbt-server' '0'); do
            hydra -s $PORT -v -V -o "$FILE_PATH/DA/PASSWORD/cred_rdp" -L $USERLIST_HYDRA_RDP -P $PASSLIST_HYDRA_RDP -t $HYDRA_THREADS $HOST rdp &> "$FILE_PATH/DA/EVIDENCE/rdp_attack"
            print_std "$(grep 'host:' "$FILE_PATH/DA/PASSWORD/cred_rdp" || echo 'PASSWORD NOT FOUND')"
            done;
        }
        
        tcp_service_on 'open' 'ms-wbt-server' '1' && {
            print_succ 'starting dictionary attack against SSL/RDP service...';
            for PORT in $(print_portid 'open' 'ms-wbt-server' '1'); do
            hydra -S -s $PORT -v -V -o "$FILE_PATH/DA/PASSWORD/cred_ssl_rdp" -L $USERLIST_HYDRA_RDP -P $PASSLIST_HYDRA_RDP -t $HYDRA_THREADS $HOST rdp &> "$FILE_PATH/DA/EVIDENCE/ssl_rdp_attack"
            print_std "$(grep 'host:' "$FILE_PATH/DA/PASSWORD/cred_ssl_rdp" || echo 'PASSWORD NOT FOUND')"
            done;
        }

        #mysql
        tcp_service_on 'open' 'mysql' '0' && {
            print_succ 'starting dictionary attack against MySQL service...';
            for PORT in $(print_portid 'open' 'mysql' '0'); do
            hydra -s $PORT -v -V -o "$FILE_PATH/DA/PASSWORD/cred_mysql" -L $USERLIST_HYDRA_MYSQL -P $PASSLIST_HYDRA_MYSQL -t $HYDRA_THREADS $HOST mysql &> "$FILE_PATH/DA/EVIDENCE/mysql_attack"
            print_std "$(grep 'host:' "$FILE_PATH/DA/PASSWORD/cred_mysql" || echo 'PASSWORD NOT FOUND')"
            done;
        }

        #smb
        tcp_service_on 'open' 'microsoft-ds' '0' && {
            print_succ 'starting dictionary attack against SMB service...';
            for PORT in $(print_portid 'open' 'microsoft-ds' '0'); do
            hydra -s $PORT -v -V -o "$FILE_PATH/DA/PASSWORD/cred_smb" -L $USERLIST_HYDRA_SMB -P $PASSLIST_HYDRA_SMB -t $HYDRA_THREADS $HOST smb &> "$FILE_PATH/DA/EVIDENCE/smb_attack"
            print_std "$(grep 'host:' "$FILE_PATH/DA/PASSWORD/cred_smb" || echo 'PASSWORD NOT FOUND')"
            done;
        }

        #ftp
        tcp_service_on 'open' 'ftp' '0' && {
            print_succ 'starting dictionary attack against FTP service...';
            for PORT in $(print_portid 'open' 'ftp' '0'); do
            hydra -s $PORT -v -V -o "$FILE_PATH/DA/PASSWORD/cred_ftp" -L $USERLIST_HYDRA_FTP -P $PASSLIST_HYDRA_FTP -t $HYDRA_THREADS $HOST ftp &> "$FILE_PATH/DA/EVIDENCE/ftp_attack"
            print_std "$(grep 'host:' "$FILE_PATH/DA/PASSWORD/cred_ftp" || echo 'PASSWORD NOT FOUND')"
            done;
        }

        #telnet
        tcp_service_on 'open' 'telnet' '0' && {
            print_succ 'starting dictionary attack against Telnet service...';
            for PORT in $(print_portid 'open' 'telnet' '0'); do
            hydra -s $PORT -v -V -o "$FILE_PATH/DA/PASSWORD/cred_telnet" -L $USERLIST_HYDRA_TELNET -P $PASSLIST_HYDRA_TELNET -t $HYDRA_THREADS $HOST telnet &> "$FILE_PATH/DA/EVIDENCE/telnet_attack"
            print_std "$(grep 'host:' "$FILE_PATH/DA/PASSWORD/cred_telnet" || echo 'PASSWORD NOT FOUND')"
            done;
        }

        #vnc (no username, password-only)
        tcp_service_on 'open' 'vnc' '0' && {
            print_succ 'starting dictionary attack against VNC service...';
            for PORT in $(print_portid 'open' 'vnc' '0'); do
            hydra -s $PORT -v -V -o "$FILE_PATH/DA/PASSWORD/cred_vnc" -P $PASSLIST_HYDRA_VNC -t $HYDRA_THREADS $HOST vnc &> "$FILE_PATH/DA/EVIDENCE/vnc_attack"
            print_std "$(grep 'host:' "$FILE_PATH/DA/PASSWORD/cred_vnc" || echo 'PASSWORD NOT FOUND')"
            done;
        }

        #postgresql
        tcp_service_on 'open' 'postgresql' '0' && {
            print_succ 'starting dictionary attack against PostgreSQL service...';
            for PORT in $(print_portid 'open' 'postgresql' '0'); do
            hydra -s $PORT -v -V -o "$FILE_PATH/DA/PASSWORD/cred_postgresql" -L $USERLIST_HYDRA_POSTGRESQL -P $PASSLIST_HYDRA_POSTGRESQL -t $HYDRA_THREADS $HOST postgres &> "$FILE_PATH/DA/EVIDENCE/postgresql_attack"
            print_std "$(grep 'host:' "$FILE_PATH/DA/PASSWORD/cred_postgresql" || echo 'PASSWORD NOT FOUND')"
            done;
        }

        #mssql
        tcp_service_on 'open' 'ms-sql-s' '0' && {
            print_succ 'starting dictionary attack against MSSQL service...';
            for PORT in $(print_portid 'open' 'ms-sql-s' '0'); do
            hydra -s $PORT -v -V -o "$FILE_PATH/DA/PASSWORD/cred_mssql" -L $USERLIST_HYDRA_MSSQL -P $PASSLIST_HYDRA_MSSQL -t $HYDRA_THREADS $HOST mssql &> "$FILE_PATH/DA/EVIDENCE/mssql_attack"
            print_std "$(grep 'host:' "$FILE_PATH/DA/PASSWORD/cred_mssql" || echo 'PASSWORD NOT FOUND')"
            done;
        }

        #snmp (UDP, community-string only, no username)
        udp_service_on 'snmp' && {
            print_succ 'starting dictionary attack against SNMP service...';
            for PORT in $(print_portid_udp 'snmp'); do
            hydra -s $PORT -v -V -o "$FILE_PATH/DA/PASSWORD/cred_snmp" -P $PASSLIST_HYDRA_SNMP -t $HYDRA_THREADS $HOST snmp &> "$FILE_PATH/DA/EVIDENCE/snmp_attack"
            print_std "$(grep 'host:' "$FILE_PATH/DA/PASSWORD/cred_snmp" || echo 'PASSWORD NOT FOUND')"
            done;
        }
    fi

    #** generate consolidated HTML report (REPORT) **#

    if [[ "$PHASE" =~ 'r' || "$PHASE" == '' ]]; then
        print_phase 'generating report...'
        generate_report
    fi

  ) &

done

# wait for any still-running host scans (relevant when PARALLEL_JOBS > 1)
wait
######## END EXPLOITATION ######

print_start_end " END SCRIPT AT `date` "

if [[ "$shutdown" == 'YES' || "$shutdown" == 'yes'  ]]; then 
    print_std 'shutdown system...'
    sleep 2
    shutdown now
fi
