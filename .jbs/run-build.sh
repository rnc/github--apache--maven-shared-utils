#!/usr/bin/env bash
set -o verbose
set -eu
set -o pipefail

#fix this when we no longer need to run as root
export HOME=/root

export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"
export JAVA_HOME=/lib/jvm/java-1.8.0
export GRADLE_USER_HOME="/var/workdir/software/settings/.gradle"
# This might get overridden by the tool home configuration below. This is
# useful if Gradle/Ant also requires Maven configured.
export MAVEN_HOME=/opt/maven/3.8.8
# If we run out of memory we want the JVM to die with error code 134
export MAVEN_OPTS="-XX:+CrashOnOutOfMemoryError"
# If we run out of memory we want the JVM to die with error code 134
export JAVA_OPTS="-XX:+CrashOnOutOfMemoryError"
export MAVEN_HOME=/opt/maven/3.8.8

mkdir -p /var/workdir/workspace/artifacts /var/workdir/workspace/logs /var/workdir/workspace/packages /var/workdir/software/settings ${HOME}/.sbt/1.0 ${GRADLE_USER_HOME}
cd /var/workdir/workspace/source

if [ ! -z ${JAVA_HOME+x} ]; then
    echo "JAVA_HOME:$JAVA_HOME"
    PATH="${JAVA_HOME}/bin:$PATH"
fi

if [ ! -z ${MAVEN_HOME+x} ]; then
       echo "MAVEN_HOME:$MAVEN_HOME"
        PATH="${MAVEN_HOME}/bin:$PATH"

        if [ ! -d "${MAVEN_HOME}" ]; then
            echo "Maven home directory not found at ${MAVEN_HOME}" >&2
            exit 1
        fi

        if [ ! z ${CACHE_URL+x} ]; then
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
        else
            cat >"/var/workdir/software/settings"/settings.xml <<EOF
            <settings>
EOF
        fi
        cat >>"/var/workdir/software/settings"/settings.xml <<EOF
          <!-- Off by default, but allows a secondary Maven build to use results of prior (e.g. Gradle) deployment -->
          <profiles>
            <profile>
              <id>secondary</id>
              <activation>
                <activeByDefault>true</activeByDefault>
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
fi

if [ ! -z ${GRADLE_HOME+x} ]; then
    echo "GRADLE_HOME:$GRADLE_HOME"
    PATH="${GRADLE_HOME}/bin:$PATH"

    if [ ! -d "${GRADLE_HOME}" ]; then
        echo "Gradle home directory not found at ${GRADLE_HOME}" >&2
        exit 1
    fi

    cat > "${GRADLE_USER_HOME}"/gradle.properties << EOF
    org.gradle.console=plain

    # Increase timeouts
    systemProp.org.gradle.internal.http.connectionTimeout=600000
    systemProp.org.gradle.internal.http.socketTimeout=600000
    systemProp.http.socketTimeout=600000
    systemProp.http.connectionTimeout=600000

    # Settings for <https://github.com/vanniktech/gradle-maven-publish-plugin>
    RELEASE_REPOSITORY_URL=file:/var/workdir/workspace/artifacts
    RELEASE_SIGNING_ENABLED=false
    mavenCentralUsername=
    mavenCentralPassword=

    # Default values for common enforced properties
    sonatypeUsername=jbs
    sonatypePassword=jbs

EOF
fi

if [ ! -z ${ANT_HOME+x} ]; then
    echo "ANT_HOME:$ANT_HOME"
    PATH="${ANT_HOME}/bin:$PATH"

    if [ ! -d "${ANT_HOME}" ]; then
        echo "Ant home directory not found at ${ANT_HOME}" >&2
        exit 1
    fi

    if [ ! z ${CACHE_URL+x} ]; then
        cat > ivysettings.xml << EOF
    <ivysettings>
        <property name="cache-url" value="${CACHE_URL}"/>
        <property name="default-pattern" value="[organisation]/[module]/[revision]/[module]-[revision](-[classifier]).[ext]"/>
        <property name="local-pattern" value="\${user.home}/.m2/repository/[organisation]/[module]/[revision]/[module]-[revision](-[classifier]).[ext]"/>
        <settings defaultResolver="defaultChain"/>
        <resolvers>
            <ibiblio name="default" root="\${cache-url}" pattern="\${default-pattern}" m2compatible="true"/>
            <filesystem name="local" m2compatible="true">
                <artifact pattern="\${local-pattern}"/>
                <ivy pattern="\${local-pattern}"/>
            </filesystem>
            <chain name="defaultChain">
                <resolver ref="local"/>
                <resolver ref="default"/>
            </chain>
        </resolvers>
    </ivysettings>
EOF
    fi
fi

if [ ! -z ${SBT_DIST+x} ]; then
    echo "SBT_DIST:$SBT_DIST"
    PATH="${SBT_DIST}/bin:$PATH"

    if [ ! -d "${SBT_DIST}" ]; then
        echo "SBT home directory not found at ${SBT_DIST}" >&2
        exit 1
    fi

    if [ ! z ${CACHE_URL+x} ]; then
        cat > "$HOME/.sbt/repositories" <<EOF
        [repositories]
          local
          my-maven-proxy-releases: ${CACHE_URL}
EOF
    fi
    # TODO: we may need .allowInsecureProtocols here for minikube based tests that don't have access to SSL
    cat >"$HOME/.sbt/1.0/global.sbt" <<EOF
    publishTo := Some(("MavenRepo" at s"file:/var/workdir/workspace/artifacts")),
EOF


fi
echo "PATH:$PATH"

#!/bin/sh
export MAVEN_HOME=/opt/maven/3.8.8
export ENFORCE_VERSION=
export PROJECT_VERSION=3.3.4

set -- "$@" install -DallowIncompleteProjects -Danimal.sniffer.skip -Dcheckstyle.skip -Dcobertura.skip -Denforcer.skip -Dformatter.skip -Dgpg.skip -Dimpsort.skip -Djapicmp.skip -Dmaven.javadoc.failOnError=false -Dmaven.site.deploy.skip -Dpgpverify.skip -Drat.skip=true -Drevapi.skip -Dsort.skip -Dspotbugs.skip -Dspotless.check.skip=true -DskipTests org.apache.maven.plugins:maven-deploy-plugin:3.1.1:deploy 

#!/usr/bin/env bash

cd /var/workdir/workspace/source

if [ -n "" ]
then
    cd 
fi



#This is replaced when the task is created by the golang code


#!/usr/bin/env bash

if [ ! -z ${ENFORCE_VERSION+x} ]; then
  echo "Setting version to ${PROJECT_VERSION} to match enforced version"
  mvn -B -e -s "/var/workdir/software/settings/settings.xml" -t "/var/workdir/software/settings/toolchains.xml" org.codehaus.mojo:versions-maven-plugin:2.8.1:set -DnewVersion="${PROJECT_VERSION}" | tee /var/workdir/workspace/logs/enforce-version.log
fi

echo "Running Maven command with arguments: $@"

#we can't use array parameters directly here
#we pass them in as goals
mvn -V -B -e -s "/var/workdir/software/settings/settings.xml" -t "/var/workdir/software/settings/toolchains.xml" "$@" "-DaltDeploymentRepository=local::file:/var/workdir/workspace/artifacts" | tee /var/workdir/workspace/logs/maven.log



