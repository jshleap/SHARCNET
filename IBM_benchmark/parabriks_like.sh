#!/bin/bash
###############################
# parabriks-like germline pipeline
################################
set -e
shopt -s expand_aliases

if [[ $(arch) = ppc64le ]]
then
  export GATK_HOME=/bio/apps/gatk_4.1.4/gatk-4.1.4.1
  export GATK_LOCAL_JAR=$GATK_HOME/libs/gatk.jar
  export GATK_SPARK_JAR=$GATK_HOME/libs/gatk-spark.jar
  export LD_LIBRARY_PATH=$GATK_HOME/libs:$LD_LIBRARY_PATH
  alias timeit='/usr/bin/time'
else
  alias timeit='/cvmfs/soft.computecanada.ca/nix/var/nix/profiles/16.09/bin/time'
fi

workPath=$1
if [ -z "${workPath}" ]
then
  workPath="${PWD}"
fi

ref="${workPath}"/Homo_sapiens_assembly38.fa
ref_dir=/home/jshleap/projects/def-jshleap/IBM_benchmark/references
illumina11=${ref_dir}/illumina/SRR10916731T_1.fastq
illumina12=${ref_dir}/illumina/SRR10916731T_2.fastq

opts="-Xmx32G -XX:+PrintGCDetails -Djava.io.tmpdir=/tmp"
opts="${opts} -DGATK_STACKTRACE_ON_USER_EXCEPTION=true -Djava.library.path=$GATK_HOME/libs"
td=/var/tmp
GR='@RG\tID:sample_rg1\tLB:lib1\tPL:bar\tSM:sample\tPU:sample_rg1'
# Run bwa-mem and pipe output to create sorted bam
if [[ $(arch) = ppc64le ]]; then
  bwa mem -t 32 -K 10000000 -R "${GR}" "${ref}" ${illumina11} ${illumina12} | \
  java -Xmx32G -XX:+PrintGCDetails -Djava.io.tmpdir=/tmp -DGATK_STACKTRACE_ON_USER_EXCEPTION=true \
  -Djava.library.path=/bio/apps/gatk_4.1.4/gatk-4.1.4.1/libs -Dsnappy.disable=true \
  -jar /bio/apps/biobuilds-2017.11/libexec/picard/picard.jar SortSam I=/dev/stdin \
  O=cpu.bam MAX_RECORDS_IN_RAM=5000000 \
  SORT_ORDER=coordinate TMP_DIR="${td}"
else
  bwa mem -t 32 -K 10000000 -R "${GR}" "${ref}" ${illumina11} ${illumina12} | \
  gatk SortSam --java-options  "${opts}" --MAX_RECORDS_IN_RAM=5000000 -I=/dev/stdin \
  -O=cpu.bam --SORT_ORDER=coordinate --TMP_DIR="${td}"
fi
# Mark Duplicates
gatk MarkDuplicates --java-options "${opts}" -I=cpu.bam -O=mark_dups_cpu.bam \
-M=metrics.txt --TMP_DIR="${td}"

# Generate BQSR Report
gatk BaseRecalibrator --java-options "${opts}" --input mark_dups_cpu.bam --output \
recal_cpu.txt --known-sites "${ref_dir}"/dbsnp_146.hg38.vcf.gz \
--known-sites "${ref_dir}"/Homo_sapiens_assembly38.known_indels.vcf.gz \
--known-sites "${ref_dir}"/Mills_and_1000G_gold_standard.indels.hg38.vcf.gz \
--reference "${ref}"

# Run ApplyBQSR Step
gatk ApplyBQSR --java-options "${opts}" -R "${ref}" -I=mark_dups_cpu.bam \
--bqsr-recal-file=recal_cpu.txt -O=cpu_nodups_BQSR.bam

#Run Haplotype Caller
gatk HaplotypeCaller --java-options "${opts}" --input cpu_nodups_BQSR.bam \
--output result_cpu.vcf --reference "${ref}" --native-pair-hmm-threads 16
