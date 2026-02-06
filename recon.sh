#!/bin/bash

PROXY=""
# Regex for noise to ignore
EXTENSIONS="png,jpg,jpeg,gif,svg,ico,woff,woff2,ttf,otf,css,mp4,mp3"

while getopts "d:l:p" opt; do
  case $opt in
    d) TARGET=$OPTARG ;;
    l) TARGET_FILE=$OPTARG ;;
    p) PROXY="http://127.0.0.1:8080" ;;
    *) echo "Usage: $0 -d domain [-l list.txt] [-p]"; exit 1 ;;
  esac
done

if [ -z "$TARGET" ] && [ -z "$TARGET_FILE" ]; then
    echo "Error: Use -d for domain or -l for list."
    exit 1
fi

# 1. Subdomain Discovery (Fast & Silent)
echo "[+] Discovering subdomains..."
if [ ! -z "$TARGET" ]; then
    (subfinder -d $TARGET -silent & assetfinder --subs-only $TARGET & curl -s "https://crt.sh/?q=%25.$TARGET&output=json" | jq -r '.[].name_value') | sed 's/\*\.//g' | sort -u > tmp_subs.txt
else
    subfinder -dL $TARGET_FILE -silent | sort -u > tmp_subs.txt
fi

# Pro Verification (Send only live subs to Burp)
HTTPX_CMD="httpx -silent -fc 404"
[ ! -z "$PROXY" ] && HTTPX_CMD="$HTTPX_CMD -proxy $PROXY"

cat tmp_subs.txt | $HTTPX_CMD > live-subs.txt
rm tmp_subs.txt

# 2. URL Discovery & Crawling
echo "[+] Collecting URLs (Filtering noise for Burp)..."
(cat live-subs.txt | waybackurls & cat live-subs.txt | gau --threads 10) | grep -iEv "\.($EXTENSIONS)$" > tmp_urls.txt

# Katana Crawl (Excluding noise via -ef flag)
KATANA_CMD="katana -list live-subs.txt -silent -nc -jc -ef $EXTENSIONS"
[ ! -z "$PROXY" ] && KATANA_CMD="$KATANA_CMD -proxy $PROXY"

$KATANA_CMD >> tmp_urls.txt
sort -u tmp_urls.txt > live-urls.txt
rm tmp_urls.txt

# 3. JS and Endpoint Extraction
echo "[+] Organizing results..."
grep -E "\.js(\?|$)" live-urls.txt > js-file.txt
grep -E "api|v1|v2|v3|admin|config|env|php|aspx|git|backup|wp-json" live-urls.txt | grep -vE "\.($EXTENSIONS)$" > interested-endpoint.txt

echo -e "\n[✔] Recon Complete."
echo "[*] Live Subs: $(wc -l < live-subs.txt)"
echo "[*] Interesting Endpoints: $(wc -l < interested-endpoint.txt)"
