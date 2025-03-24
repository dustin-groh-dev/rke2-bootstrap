## This directory is to hold the work being done to `rke2-bootstrap` script. <br/>
The file `in-process.sh` should be considered alpha and may break if you try to use it. <br/>

_I'll attempt to keep this updated with the work that's currently being done on this script that will eventually get pushed to the main script._


## Current work
Most recent work is removing the `RKE2_VERSION` variable and have the script query girhub for the latest stable RKE2 release as a default. 
Currently this adds a few seconds of startup delay to the script because of the query to the github API below.

```
RKE2_VERSION=$(curl -s "https://api.github.com/repos/rancher/rke2/releases?per_page=10" | \
jq -r '.[].tag_name' | \
grep -v 'rc' | \
sort -V | \
tail -n1)
```

Working to limit this delay. <br/>
**Once complete you could just let the script run and it'll install the latest stable RKE2 version or you can manually enter the version you'd like.**

### Outstanding work
- add error handling
- add TLS-san prompt
