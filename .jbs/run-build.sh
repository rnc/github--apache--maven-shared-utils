#!/bin/sh
export MAVEN_HOME=/opt/maven/3.8.8
export JAVA_HOME=/lib/jvm/java-1.8.0
export ENFORCE_VERSION=

set -- "$@" install -DallowIncompleteProjects -Danimal.sniffer.skip -Dcheckstyle.skip -Dcobertura.skip -Denforcer.skip -Dformatter.skip -Dgpg.skip -Dimpsort.skip -Djapicmp.skip -Dmaven.javadoc.failOnError=false -Dmaven.site.deploy.skip -Dpgpverify.skip -Drat.skip=true -Drevapi.skip -Dsort.skip -Dspotbugs.skip -Dspotless.check.skip=true -DskipTests org.apache.maven.plugins:maven-deploy-plugin:3.1.1:deploy 

#!/usr/bin/env bash
## KEYSTORE.SH
set -o verbose
set -eu
set -o pipefail
FILE="$JAVA_HOME/lib/security/cacerts"
ls -l $FILE
ls -l /var/workdir/software/tls/service-ca.crt
if [ ! -f "$FILE" ]; then
    echo "### IN FILE $FILE"
    FILE="$JAVA_HOME/jre/lib/security/cacerts"
fi

if [ -f /var/workdir/software/tls/service-ca.crt/service-ca.crt ]; then
    echo "### service-ca.crt `ls -l /var/workdir/software/tls/service-ca.crt`"
    keytool -import -alias jbs-cache-certificate -keystore "$FILE" -file /var/workdir/software/tls/service-ca.crt/service-ca.crt -storepass changeit -noprompt
fi

#!/usr/bin/env bash
## BUILD-ENTRY.SH
set -o verbose
set -eu
set -o pipefail

cd /var/workdir/workspace/source

if [ -n "" ]
then
    cd 
fi

if [ ! -z ${JAVA_HOME+x} ]; then
    echo "JAVA_HOME:$JAVA_HOME"
    PATH="${JAVA_HOME}/bin:$PATH"
fi

if [ ! -z ${MAVEN_HOME+x} ]; then
    echo "MAVEN_HOME:$MAVEN_HOME"
    PATH="${MAVEN_HOME}/bin:$PATH"
fi

if [ ! -z ${GRADLE_HOME+x} ]; then
    echo "GRADLE_HOME:$GRADLE_HOME"
    PATH="${GRADLE_HOME}/bin:$PATH"
fi

if [ ! -z ${ANT_HOME+x} ]; then
    echo "ANT_HOME:$ANT_HOME"
    PATH="${ANT_HOME}/bin:$PATH"
fi

if [ ! -z ${SBT_DIST+x} ]; then
    echo "SBT_DIST:$SBT_DIST"
    PATH="${SBT_DIST}/bin:$PATH"
fi
echo "PATH:$PATH"

#fix this when we no longer need to run as root
export HOME=/root

mkdir -p /var/workdir/workspace/logs /var/workdir/workspace/packages



#This is replaced when the task is created by the golang code
echo "### PRE_BUILD_SCRIPT "


echo "### BUILD "
#!/usr/bin/env bash

if [ ! -z ${JBS_DISABLE_CACHE+x} ]; then
    cat >"/var/workdir/software/settings"/settings.xml <<EOF
    <settings>
EOF
else
    cat >"/var/workdir/software/settings"/settings.xml <<EOF
    <settings>
      <mirrors>
        <mirror>
          <id>mirror.default</id>
          <url>${CACHE_URL}</url>
          <mirrorOf>*</mirrorOf>
        </mirror>
      </mirrors>
EOF
fi

cat >>"/var/workdir/software/settings"/settings.xml <<EOF
  <!-- Off by default, but allows a secondary Maven build to use results of prior (e.g. Gradle) deployment -->
  <profiles>
    <profile>
      <id>gradle</id>
      <activation>
        <property>
          <name>useJBSDeployed</name>
        </property>
      </activation>
      <repositories>
        <repository>
          <id>artifacts</id>
          <url>file:///var/workdir/workspace/artifacts</url>
          <releases>
            <enabled>true</enabled>
            <checksumPolicy>ignore</checksumPolicy>
          </releases>
        </repository>
      </repositories>
      <pluginRepositories>
        <pluginRepository>
          <id>artifacts</id>
          <url>file:///var/workdir/workspace/artifacts</url>
          <releases>
            <enabled>true</enabled>
            <checksumPolicy>ignore</checksumPolicy>
          </releases>
        </pluginRepository>
      </pluginRepositories>
    </profile>
  </profiles>
</settings>
EOF

#!/usr/bin/env bash

mkdir -p "${HOME}/.m2/repository"

echo "MAVEN_HOME=${MAVEN_HOME}"

if [ ! -d "${MAVEN_HOME}" ]; then
    echo "Maven home directory not found at ${MAVEN_HOME}" >&2
    exit 1
fi

TOOLCHAINS_XML="/var/workdir/software/settings"/toolchains.xml

cat >"$TOOLCHAINS_XML" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<toolchains>
EOF

if [ "8" = "7" ]; then
    JAVA_VERSIONS="7:1.7.0 8:1.8.0 11:11"
else
    JAVA_VERSIONS="8:1.8.0 9:11 11:11 17:17 21:21 22:22"
fi

for i in $JAVA_VERSIONS; do
    version=$(echo $i | cut -d : -f 1)
    home=$(echo $i | cut -d : -f 2)
    cat >>"$TOOLCHAINS_XML" <<EOF
  <toolchain>
    <type>jdk</type>
    <provides>
      <version>$version</version>
    </provides>
    <configuration>
      <jdkHome>/usr/lib/jvm/java-$home-openjdk</jdkHome>
    </configuration>
  </toolchain>
EOF
done

cat >>"$TOOLCHAINS_XML" <<EOF
</toolchains>
EOF

if [ -n "" ]; then
  echo "Setting version to 3.3.4 to match enforced version"
  mvn -B -e -s "/var/workdir/software/settings/settings.xml" -t "/var/workdir/software/settings/toolchains.xml" org.codehaus.mojo:versions-maven-plugin:2.8.1:set -DnewVersion="3.3.4" | tee /var/workdir/workspace/logs/enforce-version.log
fi

#if we run out of memory we want the JVM to die with error code 134
export MAVEN_OPTS="-XX:+CrashOnOutOfMemoryError"

echo "Running Maven command with arguments: $@"

#we can't use array parameters directly here
#we pass them in as goals
mvn -V -B -e -s "/var/workdir/software/settings/settings.xml" -t "/var/workdir/software/settings/toolchains.xml" "$@" "-DaltDeploymentRepository=local::file:/var/workdir/workspace/artifacts" | tee /var/workdir/workspace/logs/maven.log


echo "### POST_BUILD_SCRIPT "


