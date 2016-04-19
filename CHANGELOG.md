# Change log

## Upcoming
Nothing yet.

## 1.1.5
Fixes 1 bug:
* [#12](https://github.com/usermindinc/hubot-github-pr-reporter/issues/12) Hubot forgets cron string when resubscribing room.

Adds 3 new commands to help scope `show pr` commands, detailed in [#10](https://github.com/usermindinc/hubot-github-pr-reporter/issues/10).
* `show orgs` (also `show organizations`) will now list all the orgs hubot knows about.
* `show teams` will show all the teams hubot knows about, grouped by organiation.
* `show users` will show all the users hubot knows about, grouped by organiation. You can also do `show users by team` to group the users by what team(s) they're in.
