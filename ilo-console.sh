#!/bin/bash

address=https://192.168.38.102:34043
username=Administrator
password=*********

session_key=$(
  curl -fsS \
    --insecure \
    "$address/json/login_session" \
    --data "{\"method\":\"login\",\"user_login\":\"$username\",\"password\":\"$password\"}" |
      sed 's/.*"session_key":"\([a-f0-9]\{32\}\)".*/\1/'
) || {
  echo "Error retrieving session key" >&2
  exit 1
}

jnlp=$(mktemp)

cat >"$jnlp" <<eof
<?xml version="1.0" encoding="UTF-8"?>
<jnlp spec="1.0+" codebase="$address/" href="">
<information>
    <title>Integrated Remote Console</title>
    <vendor>HPE</vendor>
    <offline-allowed></offline-allowed>
</information>
<security>
    <all-permissions></all-permissions>
</security>
<resources>
    <j2se version="1.5+" href="http://java.sun.com/products/autodl/j2se"></j2se>
    <jar href="$address/html/intgapp_228.jar" main="false" />
</resources>
<property name="deployment.trace.level property" value="basic"></property>
<applet-desc main-class="com.hp.ilo2.intgapp.intgapp" name="iLOJIRC" documentbase="$address/html/java_irc.html" width="1" height="1">
    <param name="RCINFO1" value="$session_key"/>
    <param name="RCINFOLANG" value="en"/>
    <param name="INFO0" value="7AC3BDEBC9AC64E85734454B53BB73CE"/>
    <param name="INFO1" value="17988"/>
    <param name="INFO2" value="composite"/>
</applet-desc>
<update check="background"></update>
</jnlp>
eof

nohup sh -c "$HOME/Applications/jre-8/bin/javaws -wait $jnlp; rm $jnlp" >/dev/null 2>&1 &
