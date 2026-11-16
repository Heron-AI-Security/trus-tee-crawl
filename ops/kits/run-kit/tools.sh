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
RK_LEGACY_ENV="IMG OUT VMM VMW VMWBASE BUILDER MANIFEST_VM SEAL_DISK SEALER KVER COMMIT_FILE SRC_TGZ SRC_SHA BASE_IMAGE LOCKMODE EXPORT_BUCKET EXPORT_SA PIN_COMMIT SCRATCH_GB EXTRA_LABELS F2MODE DRY CONFIRM HADOOP_ALLOW_SLOW ZONE_LIST SEAL_FROM"
