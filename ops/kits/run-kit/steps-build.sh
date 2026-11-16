#!/usr/bin/env bash
# The steps of the build, once per commit, in order. Format: NUMBER|ID|TITLE|SCRIPT   (SCRIPT is - while a step is not written yet).
RK_STEPS=(
  "0|check-source|Check the source and the packages|steps/00-check-source.sh"
  "1|build-twice|Build the image twice|-"
  "2|compare-builds|Compare the two builds|-"
  "3|seal-images|Seal both images|-"
  "4|cross-check|Publish the reference values and cross-check the two images|-"
  "5|build-record|Write the build record|-"
)
