#!/usr/bin/env bash
# Rehearsal of a CLUSTER script with the REAL Hadoop shell, in a sandbox (root, a JDK 11, Hadoop's client jars): the real wrapper over a fake HDFS (a local folder), the real keys in /run/tc,
# `runuser` as the real user hadoop, and `hdfs dfs` = Hadoop's own FsShell. So an option that does not exist, or a command that fails, is found here and not on the fleet.
#   ATTESTED_HCP='/path/to/hadoop/jars/*' ATTESTED_CLASSES=/path/to/compiled/classes bash f4-local.sh SCRIPT [args]      (e.g. SCRIPT = ops/image/test/f4-attacks.sh)
set -uo pipefail
SCRIPT="${1:?usage: $0 SCRIPT [args]}"; shift
HCP="${ATTESTED_HCP:?set ATTESTED_HCP to the Hadoop client jars (a folder/*)}"; CLS="${ATTESTED_CLASSES:?set ATTESTED_CLASSES to the compiled wrapper and test classes}"; JH="${JAVA_HOME_11:-/usr/lib/jvm/java-11-openjdk-amd64}"
[ "$(id -u)" = 0 ] || { echo "needs root (runuser, /run/tc, /opt/hadoop)"; exit 2; }
id hadoop >/dev/null 2>&1 || useradd -m hadoop
rm -rf /run/tc /opt/hadoop /tmp/fakeroot /var/log/hadoop; mkdir -p /run/tc/conf /opt/hadoop/bin /tmp/fakeroot /var/log/hadoop; chmod 777 /tmp/fakeroot /var/log/hadoop
openssl ecparam -name prime256v1 -genkey -noout 2>/dev/null | openssl pkcs8 -topk8 -nocrypt -out /run/tc/sign.key 2>/dev/null
PUB="$(openssl ec -in /run/tc/sign.key -pubout -outform DER 2>/dev/null | base64 -w0)"; printf '%s' "$PUB" > /run/tc/sign.pub
printf '# tc-fleet v1\nnode0\tmaster\t10.10.0.1\t10.0.0.1:51820\t%s\tQUJD\nnode1\tworker\t10.10.0.2\t10.0.0.2:51820\t%s\tQUJD\n' "$PUB" "$PUB" > /run/tc/fleet.tsv
chgrp hadoop /run/tc/sign.key; chmod 640 /run/tc/sign.key; chmod 644 /run/tc/sign.pub /run/tc/fleet.tsv; chmod 755 /run/tc /run/tc/conf
cat > /run/tc/conf/core-site.xml <<XML
<configuration>
<property><name>fs.defaultFS</name><value>hdfs://fake:9000</value></property>
<property><name>fs.hdfs.impl</name><value>org.apache.nutch.attested.AttestedFsSmoke\$FakeWrapper</value></property>
<property><name>fs.AbstractFileSystem.hdfs.impl</name><value>org.apache.nutch.attested.AttestedFsSmoke\$FakeAdapter</value></property>
</configuration>
XML
cat > /opt/hadoop/bin/hdfs <<STUB
#!/usr/bin/env bash
# stand-in for the hdfs launcher: "hdfs dfs ARGS" runs Hadoop's own FsShell; the plain implementation is the fake HDFS (a local folder)
[ "\$1" = dfs ] || { echo "stub: only dfs"; exit 2; }; shift
args=(); for a in "\$@"; do args+=("\${a//org.apache.hadoop.hdfs.DistributedFileSystem/org.apache.nutch.attested.AttestedFsSmoke\\\$FakeHdfs}"); done
exec $JH/bin/java -cp "$CLS:/run/tc/conf:$HCP" -Dfake.root=/tmp/fakeroot org.apache.hadoop.fs.FsShell "\${args[@]}" 2> >(grep -v SLF4J >&2)
STUB
printf '#!/usr/bin/env bash\n[ "$1" = classpath ] && echo "%s:/run/tc/conf:%s" || exit 2\n' "$CLS" "$HCP" > /opt/hadoop/bin/hadoop
chmod +x /opt/hadoop/bin/*
export JAVA_TOOL_OPTIONS="-Dfake.root=/tmp/fakeroot"
bash "$SCRIPT" "$@"; rc=$?
rm -rf /run/tc /opt/hadoop /tmp/fakeroot /var/log/hadoop   # the harness leaves nothing behind (a fake /run/tc made the key tests think that they were on a node)
exit $rc
