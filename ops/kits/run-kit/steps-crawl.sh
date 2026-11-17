#!/usr/bin/env bash
# The steps of a crawl, once per configuration, in order (they go on from the build). Format: NUMBER|ID|TITLE|SCRIPT   (SCRIPT is - while a step is not written yet).
RK_STEPS=(
  "6|check-build|Check the image before using it|steps/06-check-build.sh"
  "7|start-fleet|Start the fleet|-"
  "8|form-fleet|Form the fleet|-"
  "9|check-nodes|Check every node|-"
  "10|crawl-export|Crawl and export|-"
  "11|verify-run|Verify the run against the build|-"
  "12|verify-export|Verify the export end to end|-"
  "13|clean-up|Delete the fleet|-"
)
