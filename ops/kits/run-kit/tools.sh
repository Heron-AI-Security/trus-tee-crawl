#!/usr/bin/env bash
# tools.sh: the ONE file of the kit that spells the file names of the older tools of the repository. The stages call the tools through these variables, so a
# rename of a tool (the cleanup at the end of the project) changes this file and nothing else. The rehearsal of the runner checks that no other file of the kit
# carries an old step label or an old tool name. The stages print plain sentences; what a tool printed itself goes to the log files.

RK_T_ARCHIVE_CHECK=ops/image/test/r4-archive.py     # reads the commit id out of a git archive and refuses an archive of another commit
RK_REHEARSAL_DIR=ops/image/test                      # where the rehearsals of the repository are
RK_REHEARSALS_AS_ROOT="r3-rehearse"                  # the rehearsals that need sudo
RK_REHEARSALS_DEFAULT="${RK_REHEARSALS_DEFAULT:-fetchlist-rehearse r5-rehearse p4d-rehearse r4-rehearse r4b-rehearse r4c-rehearse r4d-rehearse r4e-rehearse r4f-rehearse r4g-rehearse r4h-rehearse r4i-rehearse r4j-rehearse p1-rehearse p2a-rehearse f03-drive-rehearse f03c-rehearse r3-rehearse f4-rehearse f1-rehearse}"   # the full list; RK_REHEARSALS (in the environment) runs a shorter list for a quick try, and that never counts as the full list
# the files that the later steps use and that must be in the commit that is built (it is better to know now than after hours)
RK_REQUIRED_FILES="ops/ci/publish-ref.sh ops/verify-reference.sh ops/verify-reference.py ops/tree-diff.sh ops/tree-helper.sh ops/tree-lib.sh ops/image/build/tc-image-normalize.sh ops/verify-export.py ops/attested/verify_export_records.py ops/attested/verify_endorsement.py ops/attested/verify_fetchlist.py ops/image/test/fetchlist-rehearse.sh ops/image/test/verify-export-rehearse.py ops/attested/verify_intel_chain.py ops/attested/verify_intel_chain_rehearse.py ops/attested/verify_time_export.py ops/attested/verify_time_export_rehearse.py ops/attested/sp/custody/roughtime.py ops/attested/sp/verify/time-servers.json ops/image/rootfs/usr/local/lib/tc/tc-peer-verify.py src/java/org/commoncrawl/util/TcFetchLedger.java ops/image/test/r5-rehearse.sh"
# the environment variables that the older tools read. The kit clears them when it starts, so that nothing inherited from the shell (a DRY=1, a CONFIRM=yes, an IMG of an earlier session)
# changes what a tool does; a step sets the ones that it needs, in front of the one command that needs them.
RK_LEGACY_ENV="IMG OUT VMM VMW VMWBASE BUILDER MANIFEST_VM SEAL_DISK SEALER SEAL_TEST KVER COMMIT_FILE SRC_TGZ SRC_SHA BASE_IMAGE LOCKMODE EXPORT_BUCKET EXPORT_SA PIN_COMMIT SCRATCH_GB EXTRA_LABELS F2MODE DRY CONFIRM HADOOP_ALLOW_SLOW ZONE_LIST SEAL_FROM"

RK_T_IMAGE_DRIVER=ops/image/test/f03-drive.sh        # makes a builder VM and builds the image on it, one stage at a time (the stage names below are its own)
RK_BUILD_STAGES="ship-builder debs prep fetch-hadoop bake ship-source job bake-crawl bake-fleet debs-audit bake-seal manifest"   # fetch-hadoop is the kit's own stage; the others are stages of the driver
RK_CAPACITY_RX='ZONE_RESOURCE_POOL_EXHAUSTED|does not have enough resources|is currently unavailable|resource_availability'   # what the cloud says when a zone has no room: only then is the next zone tried

RK_T_COMPARE_BUILDS=ops/image/test/r4-diff.py        # compares the measurements of two builds event by event
RK_T_DERIVE_RECIPE=ops/image/test/r4-derive.py       # derives the install recipe of a build from its measurements
RK_T_RECOMPUTE=ops/image/test/r4-recompute.py        # recomputes the stable measurements from the commit alone, with that recipe
# the lines that those tools print when all is well (the steps print plain sentences; these are only what they look for)
RK_M_EVENTS_EQUAL='^R4-DIFF: ([0-9]+) of \1 events identical; different: none'
RK_M_DIFF_LINE='^R4-DIFF'                                  # the summary line of the comparison tool, shown only when the comparison fails
RK_M_DIFF_COUNT='^R4-DIFF: ([0-9]+) of .*'                 # its first number: how many events the comparison covered
RK_M_PACKAGES_EQUAL='packages: A [0-9]*, B [0-9]*; all versions equal'
RK_M_INITRD_SAME='initrd.img-tc  *same'
RK_M_RECOMPUTE_OK='^R4-RECOMPUTE-OK: ([0-9]+) of ([0-9]+)'

RK_T_SEAL_PREFLIGHT=ops/image/test/r3-preflight.sh   # read-only check of everything that the sealing needs
RK_SEAL_BASE_IMAGE=tc-img-dbg-1                      # the image that the sealing helper VMs are made from: it exists in the project already, and the preflight checks it
RK_SEAL_STAGES="builder ship-builder seal-locked seal-disk"   # the driver stages that lock, clean and power off the builder and then seal its disk offline
RK_SEAL_IMAGE_STAGE=seal-image; RK_SEAL_CLEAN_STAGE=seal-delete   # make the image from the sealed disk; delete the helper VM and the copied disk
RK_SEAL_CONSOLE=f4-seal-console.txt                  # the console file of the lock stage: the driver writes SEAL-DONE there when the builder is locked, cleaned and powered off
RK_M_SEAL_DONE='SEAL-DONE'; RK_M_SEAL_OK='SEAL-OK'; RK_M_NORMALIZE_OK='NORMALIZE-OK'; RK_SEAL_REPORT_FILE=normalize-report.txt

RK_T_PUBLISH_REFERENCE=ops/ci/publish-ref.sh         # two dummy runs of the published image, then the reference values and the files to publish
RK_T_VERIFY_REFERENCE=ops/verify-reference.sh        # the published image against an own build of the same commit: the files of both root disks, each opened through dm-verity
RK_CROSS_TOOLS="ops/ci/publish-ref.sh ops/verify-reference.sh ops/tree-diff.sh ops/tree-helper.sh ops/tree-lib.sh ops/verify-reference.py"
RK_M_PUBLISH_OK='^PUBLISH-REF-OK'; RK_M_VERIFY_OK='^VERIFY-REFERENCE-OK .* trees=identical image-run=exact'
RK_JOB_CONSOLE_FILE=f03-job-console.txt              # the console of the job stage of a build, in the evidence folder of the build
RK_VERIFY_DIFFS=trees/differences.tsv                # what the verify tool writes when two file trees differ
RK_HIDE_FROM_HEARTBEAT='^(PUBLISH-REF|VERIFY-REFERENCE)'   # the success lines of the long tools: a heartbeat shows a progress line, not an old marker
RK_TRANSIENT_RX='could not describe|Connection reset|Connection timed out|TLS handshake timeout|rateLimitExceeded|HTTPError 50[0-9]|Temporary failure in name resolution'   # a failed call to the cloud (it is tried again); a difference between the images never matches
RK_EXPORT_BUCKET=training-custody-export-test; RK_EXPORT_SA=tc-export@training-custody.iam.gserviceaccount.com   # where the master puts the export, and the account that may write there
RK_CRAWL_TOOLS="ops/image/test/f1-drive.sh ops/image/test/r3-export-audit.py ops/image/test/r3-receipt-verify.py ops/image/test/r4-accept.sh ops/verify-export.py"   # what the steps of a crawl run from the commit tree
