# hubot-github-pr-reporter

Show open PRs for a user, team or organization. Schedule hubot to reguarly report on open PRs.

See [`src/github-pr-reporter.coffee`](src/github-pr-reporter.coffee) for full documentation.

## Installation

In hubot project repo, run:

`npm install hubot-github-pr-reporter --save`

Then add **hubot-github-pr-reporter** to your `external-scripts.json`:

```json
[
  "hubot-github-pr-reporter"
]
```

## Dependencies

### Environment Variables
* HUBOT_GITHUB_TOKEN - used by githubot
* HUBOT_GITHUB_USER - used by githubot

### Dependencies:
* "cron-parser": "1.0.1"    - Used to parse cron string input
* "githubot": "1,0,0"       - Used to query GitHub
* "moment": "2.10.6"        - Used for report formatting
* "node-schedule": "0.5.1"  - Used for the scheduling feature
* "underscore": "1.8.3"     - Used for report formatting
* "github-credentials"      - Optional. Translates github names to @mention names.

## Sample Interaction

### Show a list of open pull requests
```
gary> hubot show prs
hubot>
@gary:
  8 hours, 0 comments, @dala, Improve reporting
  ↳ https://github.com/example/reporting/pull/42
  3 hours, 2 comments, *unassigned*, Updated readme
  ↳ https://github.com/example/reporting/pull/24
mr_house:
  *6 months*, 0 comments, benny, Updates to platinum chip
  ↳ https://github.com/example/chip/pull/101
```

You can specify:
* No options. Just `hubot show prs` to get the fire hose.
* A user to show PRs by that author, by adding a `user:githubLogin` string
* A team to show PRs authored by that team, by adding a `team:teamName` string
* An organization to show all open PRs in that org, by adding a `org:organizationName` string

Note that the order matters, and they chain when possible. For instance:
* Specifying user and org limit the responses to just that user in that org. Useful if a user has open PRs in multiple orgs, but you only care about one.
* Specifying a team and an org helps specify which team you mean, since team names aren't globally unique.

### Subscribe to PR reports
```
gary> hubot subscribe prs for user:mr_house
hubot> @gary: Great! This request will show you all PRs mentioning mr_house at the default frequency (weekdays at noon)

... then, at noon ...
hubot>
mr_house:
  *6 months*, 0 comments, benny, Updates to platinum chip
  ↳ https://github.com/example/chip/pull/101

To unsubscribe, type `hubot unsubscribe prs 5`
```
You can specify:
* The same options for name, team, and org above. Same rules apply.
* A custom frequency by specifying the cron format you want hubot to report at. You can do this by adding `cron:"your cron string"` to the command.

### Show a list of all ongoing subscriptions
```
gary> hubot show pr subscriptions
hubot>
ID   Requestor    Description
5    gary         paused => org:example
```
This will show all of the subscriptions for the room you're currently in. To see all subscriptions hubot is keeping track of, add 'all' to the request:
```
gary> hubot show all pr subscriptions
hubot>
Room           ID   Requestor    Description
engineering    5    gary         org:example
research       7    mr_house     paused => team:securitron org:example
```
A "paused" mention in the description just means hubot lost a reference to the room, and can't post to it until someone says something. As soon as there's other activity in the room, it'll automatically resume the subscription.

### Unsubscribe from a report
```
gary> hubot unsubscribe pr 5
hubot> Successfully unsubscribed from 5: all PRs in the example organization at the default frequency (weekdays at noon)
```
Note that you need to be in the room that requested the subscription in order to unsubscribe. That's so folks in that room know that the subscription was stopped, rather than something broke.
