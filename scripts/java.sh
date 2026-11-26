#!/usr/bin/env bash
set -euo pipefail

root=$1
work=$2
package=$3
python=${PYTHON:-python3}
jdk="$work/jdk"
source_dir="$work/source"
metalava="$source_dir/tools/metalava"
mkdir -p "$jdk" "$package/bin" "$package/framework" "$package/share/licenses"
tar -xzf "$root/out/inputs/tool/aosstudio-jdk-21.0.13.1-2-linux-x86_64.tar.gz" -C "$jdk"
"$jdk/bin/java" -version
bootstrap=aosstudio-aosp-host-tools-bootstrap-17.0.0_r1-linux-x86_64
tar -xzf "$root/out/dist/$bootstrap.tar.gz" -C "$work"
merge_zips="$work/$bootstrap/bin/merge_zips"

compiler_list=$("$python" "$root/scripts/inputs.py" java --jars compiler)
runtime_list=$("$python" "$root/scripts/inputs.py" java --jars metalava)
antlr_list=$("$python" "$root/scripts/inputs.py" java --jars antlr)
turbine_list=$("$python" "$root/scripts/inputs.py" java --jars turbine)
parcelables_list=$("$python" "$root/scripts/inputs.py" java --jars sdkparcelables)
mapfile -t runtime <<< "$runtime_list"
mapfile -t turbine <<< "$turbine_list"
mapfile -t parcelables <<< "$parcelables_list"
compiler=("$jdk/bin/java" -Xmx6g "-Djava.io.tmpdir=$TMPDIR" -cp "${compiler_list//$'\n'/:}"
  org.jetbrains.kotlin.cli.jvm.K2JVMCompiler -no-stdlib -no-reflect -jvm-target 17)

cd "$work"
mkdir -p antlr metalava-classes parcelables-classes
(
  cd "$metalava/metalava-model-source/src/main/antlr"
  "$jdk/bin/java" -cp "${antlr_list//$'\n'/:}" org.antlr.v4.Tool -visitor \
    -o "$work/antlr" AntlrJavadocLexer.g4 AntlrJavadocParser.g4
)
modules=(metalava-reporter metalava-model metalava-model-text metalava-model-source
  metalava-model-turbine metalava-model-psi metalava)
java_roots=()
resource_jars=()
for module in "${modules[@]}"; do
  main="$metalava/$module/src/main"
  java_roots+=("$main/java")
  if [[ -d "$main/resources" ]]; then
    "$jdk/bin/jar" --create --file "$module-resources.jar" -C "$main/resources" .
    resource_jars+=("$module-resources.jar")
  fi
done
find "${java_roots[@]}" -name '*.kt' | sort > metalava-kotlin.txt
find "${java_roots[@]}" -name '*.java' | sort > metalava-java.txt
find antlr -name '*.java' | sort > antlr-java.txt
java_source_roots=$(IFS=,; printf '%s' "${java_roots[*]}")
classpath=${runtime_list//$'\n'/:}
"$jdk/bin/javac" --release 17 -proc:none -encoding UTF-8 \
  -cp "$classpath" -d metalava-classes @antlr-java.txt
"${compiler[@]}" -classpath "metalava-classes:$classpath" "-Xjava-source-roots=$java_source_roots" \
  -module-name metalava -d metalava-classes @metalava-kotlin.txt
"$jdk/bin/javac" --release 17 -proc:none -encoding UTF-8 \
  -cp "metalava-classes:$classpath" -d metalava-classes @metalava-java.txt
cp "$metalava/version.properties" metalava-classes/
"$jdk/bin/jar" --create --file metalava-classes.jar -C metalava-classes .

find "$source_dir/frameworks/base/tools/sdkparcelables/src" -name '*.kt' | sort > parcelables.txt
"${compiler[@]}" -classpath "${parcelables_list//$'\n'/:}" -module-name sdkparcelables \
  -d parcelables-classes @parcelables.txt
"$jdk/bin/jar" --create --file sdkparcelables-classes.jar -C parcelables-classes .

printf 'Main-Class: com.android.tools.metalava.Driver\n' > metalava.mf
printf 'Main-Class: com.android.sdkparcelables.MainKt\n' > sdkparcelables.mf
printf 'Main-Class: com.google.turbine.main.Main\n' > turbine.mf
merge_options=(-j -D -ignore-duplicates
  -stripFile 'META-INF/*.SF' -stripFile 'META-INF/*.RSA' -stripFile 'META-INF/*.DSA'
  -stripFile 'META-INF/versions/**/module-info.class' -stripFile module-info.class)
"$merge_zips" "${merge_options[@]}" -m metalava.mf "$package/framework/metalava.jar" \
  metalava-classes.jar "${resource_jars[@]}" "${runtime[@]}"
"$merge_zips" "${merge_options[@]}" -m sdkparcelables.mf "$package/framework/sdkparcelables.jar" \
  sdkparcelables-classes.jar "${parcelables[@]}"
"$merge_zips" "${merge_options[@]}" -m turbine.mf "$package/framework/turbine.jar" "${turbine[@]}"

for tool in metalava sdkparcelables turbine; do
  install -m 0755 "$root/scripts/java-launcher.sh" "$package/bin/$tool"
done
install -m 0644 "$root/LICENSE" "$package/share/licenses/AOSP"
"$python" "$root/scripts/jar-notices.py" "$package/share/licenses" "${runtime[@]}" "${turbine[@]}"
JAVA_HOME="$jdk" "$package/bin/metalava" --version
