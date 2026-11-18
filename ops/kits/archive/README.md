# Archived kits

These are the kits of the earlier milestones (m481 to m522), the shared cluster kit (`tcshared`) and the three older one-command kits (`r4-r47-kit`, `psl-fix-kit`, `rel-fix-kit`). They are history, kept for the record exactly as they ran: nothing inside them was edited when they were moved here.

Archived kits keep their old internal paths. A kit that calls another kit, or a file in its own folder, by the path it had before the move (for example the five `m5xx-build` scripts call `m481-build` as `ops/kits/m481-build/...`) is not changed, so it does not find that path now. They are not meant to be run from here; a rerun would need those paths changed. The kit that stays directly under `ops/kits` is `r4-final-kit`.
