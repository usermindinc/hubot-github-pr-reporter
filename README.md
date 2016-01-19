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

```
user1>> hubot hello
hubot>> hello!
```
