{
  lib,
  stdenv,
  fetchFromGitHub,
  jdk,
  gradle_7,
  perl,
  writeText,
  makeWrapper,
  tree,
}:
let
  gradle = gradle_7;
  pname = "structurizr-cli";
  version = "2024.03.03";

  src = fetchFromGitHub {
    owner = "structurizr";
    repo = "cli";
    rev = "v${version}";
    sha256 = "sha256-V3lqx0/gku0KdeTkLqlA3ANWAUqw09PvcTccyDNljQs=";
  };

  deps = stdenv.mkDerivation {
    name = "${pname}-deps";
    inherit src;

    nativeBuildInputs = [
      jdk
      perl
      gradle
    ];

    buildPhase = ''
      export GRADLE_USER_HOME=$(mktemp -d);
      gradle --no-daemon getDeps
    '';

    # Mavenize dependency paths
    # e.g. org.codehaus.groovy/groovy/2.4.0/{hash}/groovy-2.4.0.jar -> org/codehaus/groovy/groovy/2.4.0/groovy-2.4.0.jar
    installPhase = ''
      find $GRADLE_USER_HOME/caches/modules-2 -type f -regex '.*\.\(jar\|pom\)' \
        | perl -pe 's#(.*/([^/]+)/([^/]+)/([^/]+)/[0-9a-f]{30,40}/([^/\s]+))$# ($x = $2) =~ tr|\.|/|; "install -Dm444 $1 \$out/$x/$3/$4/$5" #e' \
        | sh
    '';

    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    outputHash = "sha256-4hnGPgbsZhUlZa3zH44Kg5IxtM11Bu7WhMfwZJZPji0=";
  };

  # Point to our local deps repo
  gradleInit = writeText "init.gradle" ''
    settingsEvaluated { settings ->
      settings.pluginManagement {
        repositories {
          clear()
          maven { url '${deps}' }
        }
      }
    }
    logger.lifecycle 'Replacing Maven repositories with ${deps}...'
    gradle.projectsLoaded {
      rootProject.allprojects {
        buildscript {
          repositories {
            clear()
            maven { url '${deps}' }
          }
        }
        repositories {
          clear()
          maven { url '${deps}' }
        }
      }
    }
  '';
in
stdenv.mkDerivation rec {
  inherit pname src version;

  nativeBuildInputs = [
    jdk
    gradle
    makeWrapper
    tree
  ];

  buildPhase = ''
    runHook preBuild

    export GRADLE_USER_HOME=$(mktemp -d)
    gradle -PVERSION=${version} --offline --no-daemon --info --init-script ${gradleInit} build -x test

    runHook postBuild
  '';

  installPhase = ''
    mkdir -p $out/bin
    mkdir -p $out/share/java

    tree build
    install -Dm644 build/libs/${pname}.jar $out/share/java
    install -Dm644 build/resources/main/build.properties $out/share/java

    classpath=$(find ${deps} -name "*.jar" -printf ':%h/%f');
    # create a wrapper that will automatically set the classpath
    # this should be the paths from the dependency derivation
    makeWrapper ${jdk}/bin/java $out/bin/${pname} \
          --add-flags "-classpath $out/share/java/${pname}.jar:''${classpath#:}" \
          --add-flags "-Dspring.config.location=$out/share/build.properties" \
          --add-flags "com.structurizr.cli.StructurizrCliApplication"
  '';

  meta = with lib; {
    description = "A command line utility for Structurizr.";
    homepage = "https://github.com/structurizr/cli/tree/v2024.03.03";
    sourceProvenance = with sourceTypes; [
      fromSource
      binaryBytecode # deps
    ];
    license = licenses.asl20;
    platforms = platforms.all;
  };
}
