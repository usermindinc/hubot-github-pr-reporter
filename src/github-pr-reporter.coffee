# Description
#   Show open PRs for a user, team or organization. Schedule hubot to reguarly report on open PRs.
#
# Configuration:
#   HUBOT_GITHUB_TOKEN - used by githubot
#   HUBOT_GITHUB_USER - used by githubot
#
# Dependencies:
#    "cron-parser": "1.0.1"    - Used to parse cron string input
#    "githubot": "1,0,0"       - Used to query GitHub
#    "moment": "2.10.6"        - Used for report formatting
#    "node-schedule": "0.5.1"  - Used for the scheduling feature
#    "underscore": "1.8.3"     - Used for report formatting
#
# Commands:
#   hubot show prs for [user:user] [team:team] [org:organization] - List PRs by author, filter by user, team, or organization. If nothing is specified, it will be for all orgs that hubot can access.
#   hubot subscribe prs for [user:user] [team:team] [org:organization] [cron:"cron"] - Subscribe to a PR digest. This runs `show prs` on weekdays at noon. Specify a custom cron string to have it run with adifferent freqency.
#   hubot show (all) pr subscriptions - List PR subscriptions on the current room. Add "all" to ask about all of the subscriptions that it knows about.
#   hubot unsubscribe pr id - Stop an existing subscription by specifying its id.
#
# Notes:
#   There are also shorthand forms for these commands, but it's easier to explain without them. Feel free to
#   look below for shorthand forms of those commands.
#
# Examples:
#   hubot show prs - Show all PRs in all orgs
#   hubot show prs for user:downie - Show all PRs created by user `downie` across all orgs
#   hubot show prs for team:alpha - Show all PRs created by users in the `alpha` team. If that team is common across orgs, it will choose one for you.
#   hubot show prs for team:alpha org:usermindinc - Show all PRs created by users in the `alpha` team in the `usermindinc` org
#   hubot subscribe prs - Show all PRs in all orgs on weekdays at noon.
#   hubot subscribe prs for user:downie - Show all PRs created by user `downie` across all orgs on weekdays at noon
#   hubot subscribe prs for team:alpha - Show all PRs created by users in the `alpha` team on weekdays at noon
#   hubot subscribe prs for team:alpha org:usermindinc - Show all PRs created by users in the `alpha` team in the `usermindinc` org weekdays at noon
#   hubot subscribe prs for cron:"* * * * * *" - Show all PRs in all orgs every minute forever. Not recommended.
#   hubot show pr subscriptions - List all subscriptions in the current room
#   hubot show all pr subscriptions - List all subscriptions this hubot has in its brain.
#   hubot unsubscribe pr 34 - Stop subscription #34 from running.
#
# Author:
#   Chris Downie <cdownie@gmail.com>

cronParser = require 'cron-parser'
moment     = require 'moment'
schedule   = require 'node-schedule'
_          = require 'underscore'


# In-memory globals
organizations = []
teams = {}
subscribedRooms = []

#
# Digest object methods
#
GLOBAL_ID_COUNTER = 0
# Default frequency is Mon-Fri at noon
DEFAULT_SCHEDULE_FREQUENCY = new schedule.RecurrenceRule()
DEFAULT_SCHEDULE_FREQUENCY.dayOfWeek = new schedule.Range(1,5)
DEFAULT_SCHEDULE_FREQUENCY.hour = 12
DEFAULT_SCHEDULE_FREQUENCY.minute = 0


class DigestRequest
  constructor: (@user, @team, @organization) ->
    # Easy name properties
    @userName = @user and @user.login
    @teamName = @team and @team.name
    @organizationName = @organization and @organization.login
    # Scheduled properties, defaulting to null
    @room = null
    @requestedBy = null
    @scheduleFrequency = null
    @scheduledJob = null


  @requestFromPlainObject: (object) ->
    request = new DigestRequest object.user, object.team, object.organization
    request.id = object.id
    request.room = object.room
    request.requestedBy = object.requestedBy
    request

  description: (shouldSkipFrequency) ->
    explanation = "all PRs"
    if @userName?
      explanation += " mentioning #{@userName}"
    if @teamName?
      explanation += " in the #{@teamName} team"
    if @organizationName?
      explanation += " in the #{@organizationName} organization"
    if @scheduleFrequency?
      explanation += " with cron string \"#{@scheduleFrequency}\""
    else unless shouldSkipFrequency
      explanation += " at the default frequency (weekdays at noon)"
    explanation

  shortDescription: ->
    description = ""
    if @userName?
      description += "#{@userName}@"
    if @teamName?
      description += "team:#{@teamName} "
    if @organizationName?
      description += "org:#{@organizationName}"
    if description.length == 0
      description = "all orgs"

    if @scheduleFrequency
      description += " cron:#{@scheduleFrequency}"
    unless @scheduledJob?
      description = "paused => " + description
    description

ageOfIssue = (issue) ->
  emphasizeAfterHours = 24
  msDifference = moment().diff(moment(issue.updated_at))
  duration = moment.duration(msDifference)
  if duration.asHours() > emphasizeAfterHours
    "*#{duration.humanize()}*"
  else
    duration.humanize()

digestForRequest = (github, digestRequest, callback) ->
  # Fetch all issues, either for the single org on the request or for all orgs
  orgNameList = organizations.map (org) -> org.login
  if digestRequest.organizationName?
    orgNameList = [ digestRequest.organizationName ]

  # Get all PRs from the issues API
  promiseChain = Promise.all(orgNameList.map (orgName) ->
    new Promise (resolve, reject) ->
      github.get "orgs/#{orgName}/issues?filter=all", (issues) ->
        # Issues API returns issues & pull requests. The difference is the existence of this property
        issues = issues.filter (issue) ->
          return issue.pull_request?
        resolve issues
  )

  # Combine all those responses into one array of issues
  promiseChain = promiseChain.then (issuesSets) ->
    issuesSets.reduce(
      (previous, current) -> previous.concat(current),
      []
    )

  # Fetch multiple users from the team as needed
  promiseChain = promiseChain.then (issues) ->
    if digestRequest.user?
      [issues, [digestRequest.user]]
    else if digestRequest.team?
      new Promise (resolve, reject) ->
        github.get "teams/#{digestRequest.team.id}/members", (users) ->
          resolve [issues, users]
    else
      [issues, null]

  # Filter by matching issues to users
  promiseChain = promiseChain.then ([issues, filterByUsers]) ->
    if filterByUsers?
      filterNames = filterByUsers.map (user) -> user.login
      filterFunction = (issue) ->
        issue.user.login in filterNames
    else
      filterFunction = () -> true

    issues.filter filterFunction

  # Generate output grouped by login.
  promiseChain = promiseChain.then (issues) ->
    digest = ""
    sortedIssues = _.sortBy issues, (issue) ->
      moment(issue.updated_at)
    groupedIssues = _.groupBy sortedIssues, (issue) ->
      issue.user.login
    _.forEach groupedIssues, (issues, login) ->
      digest += "#{login}:\n"
      issues.forEach (issue) ->
        age = ageOfIssue issue
        comments = "#{issue.comments} comments"
        assignee = issue.assignee and issue.assignee.login or "*unassigned*"
        title = issue.title
        link = issue.html_url

        digest += "\t#{age}, #{comments}, #{assignee}, #{title}\n"
        digest += "\t↳ #{link}\n"
    if digest == ""
      digest = "Nothing found for #{digestRequest.description(true)}"
    callback digest
  promiseChain = promiseChain.catch (error) ->
    callback "#{digestRequest.id}: No good #{error}"

#
# Methods to run on wakeup
#
getSubscriptions = (robot) ->
  SUBSCRIPTIONS_KEY = "github-pull-request-notifier-subscriptions"
  subscriptions = robot.brain.get(SUBSCRIPTIONS_KEY)

  unless subscriptions?
    subscriptions = []
    robot.brain.set(SUBSCRIPTIONS_KEY, subscriptions)

  subscriptions.forEach (digestRequest, index) ->
    unless digestRequest instanceof DigestRequest
      request = DigestRequest.requestFromPlainObject(digestRequest)
      subscriptions[index] = request

  subscriptions

getNextId = (robot) ->
  ID_KEY = "github-pull-request-notifier-id"
  id = robot.brain.get(ID_KEY) or 0
  robot.brain.set(ID_KEY, id + 1)
  id


resubscribeRoom = (robot, github, room, res) ->
  if room in subscribedRooms
    return
  subscribedRooms.push room

  unsubscribedCount = 0
  subscriptions = getSubscriptions robot

  subscriptions.forEach (request) ->
    unless request.scheduledJob?
      if request.room == room
        frequency = request.scheduleFrequency or DEFAULT_SCHEDULE_FREQUENCY
        request.scheduledJob = schedule.scheduleJob frequency, () ->
          digestForRequest github, request, (digest) ->
            if res?
              res.send "#{digest}\n\nTo unsubscribe, type `#{robot.name} unsubscribe prs #{request.id}`\n"
      else
        unsubscribedCount++

  unsubscribedCount

refreshCachedGithubData = (github) ->
  # Fetch data that is unlikely to change frequently. Organizations and Teams for the robot.
  github.get "user/orgs", (orgs) ->
    organizations = orgs
    orgs.forEach (org) ->
      github.get "orgs/#{org.login}/teams", (teamsForThisOrg) ->
        teams[org.login] = teamsForThisOrg


#
# Main methods. These map almost 1:1 with the registered responders below.
#

parseDigestRequest = (github, userName, teamName, organizationName, callback) ->
  # These regexes are really permissive.
  # If they specify 2 things, then it's user, then organization. Validate both.
  # If they specify nothing, then we've got nothing to give.
  # But if they specify just one, then we've got some github exploring to do. Assume it's a user, try to
  # validate that first. If that fails, then try to validate it against our org list.
  error = null
  validUser = null
  validTeam = null
  validOrganization = null

  # Validate the organization
  if organizationName?
    matchingOrganization = organizations.find (org) ->
      org.login == organizationName
    if matchingOrganization?
      validOrganization = matchingOrganization
    else
      error or= "Unknown organization: #{organizationName}"

  # Validate the team
  if teamName?
    teamName = teamName.trim().toLowerCase()
    if validOrganization?
      matchingTeam = teams[validOrganization.login].find (team) ->
        team.name.trim().toLowerCase() == teamName
      if matchingTeam?
        validTeam = matchingTeam
      else
        error or= "Team #{teamName} is not in organization #{validOrganization.login}\n
You may need to invite hubot to the #{teamName} team for it to be queryable."
    else
      organizations.forEach (organization) ->
        matchingTeam = teams[organization.login].find (team) ->
          team.name.trim().toLowerCase() == teamName
        if matchingTeam?
          validTeam = matchingTeam
          validOrganization = organization
      unless validTeam?
        orgNames = organizations.map (org) -> org.login
        error or= "Team #{teamName} doesn't appear to be in any known organization: #{orgNames.join(', ')}.\n
You may need to invite hubot to the #{teamName} team for it to be queryable."


  if userName?
    userPromise = new Promise (resolve, reject) ->
      userName = userName.toLowerCase()

      # if we have a valid team, then ask for all the members of that team.
      # if we have a valid org, then ask for all the members of that org
      # if we have no other information. ask for users from all orgs and validate.
      if validTeam?
        github.get "teams/#{validTeam.id}/members", (members) ->
          matchingUser = members.find (member) ->
            member.login.toLowerCase() == userName
          if matchingUser?
            resolve matchingUser
          else
            reject "#{userName} is not a member of team #{validTeam.name}"
      else if validOrganization?
        github.get "orgs/#{validOrganization.login}/members", (members) ->
          matchingUser = members.find (member) ->
            member.login.toLowerCase() == userName
          if matchingUser
            resolve matchingUser
          else
            reject "#{userName} is not a member of organization #{validOrganization.login}"
      else
        orgMembersPromises = organizations.map (organization) ->
          new Promise (orgResolve, orgReject) ->
            github.get "orgs/#{organization.login}/members", orgResolve

        Promise.all(orgMembersPromises).then (memberSets) ->
          foundUser = null
          memberSets.forEach (members) ->
            matchingMember = members.find (member) ->
              member.login.toLowerCase() == userName
            if matchingMember? and not foundUser?
              foundUser = matchingMember
          if foundUser?
            resolve foundUser
          else
            reject "#{userName} is not a member of any known organization"

  else
    userPromise = Promise.resolve null

  promise = userPromise.then (validUser) ->
    digestRequest = new DigestRequest validUser, validTeam, validOrganization
    callback digestRequest, error

  promise = promise.catch (userError) ->
    error or= userError
    console.log "Promise failed: #{error}"
    callback null, error

scheduleDigest = (robot, github, res, request, callback) ->
  errorMessage = null
  subscriptions = getSubscriptions robot
  try
    subscriptions.push request
    frequency = request.scheduleFrequency or DEFAULT_SCHEDULE_FREQUENCY
    subscribedRooms.push request.room
    request.scheduledJob = schedule.scheduleJob frequency, () ->
      digestForRequest github, request, (digest) ->
        if res?
          res.send "#{digest}\n\nTo unsubscribe, type `#{robot.name} unsubscribe prs #{request.id}`\n"
  catch error
    errorMessage = "Error scheduling request #{request.id}: #{error}"

  callback errorMessage



#
# Robot listening registry
#
module.exports = (robot) ->
  github = require('githubot')(robot)


  refreshCachedGithubData github

  robot.brain.once "loaded", () ->
    getSubscriptions robot

  robot.respond /show prs?(?: for)?(?: user:(\w*))?(?: team:([\w-]*))?(?: org:(\w*))?$/i, (res) ->
    [ignored, user, team, org] = res.match
    parseDigestRequest github, user, team, org, (digestRequest, error) ->
      if error?
        res.send "`#{res.match[0]}` failed: #{error}"
      else
        digestRequest.id = getNextId robot
        digestForRequest github, digestRequest, (digest) ->
          res.send digest

  robot.respond /sub(?:scribe)? prs?(?: for)?(?: user:(\w*))?(?: team:([\w-]*))?(?: org:(\w*))?(?: cron:[“"”](.*)[“"”])?/i, (res) ->
    [ignored, user, team, org, cron] = res.match
    parseDigestRequest github, user, team, org, (digestRequest, error) ->
      unless error?
        if cron?
          try
            cronParser.parseExpression cron
          catch cronError
            error = cronError

      if error?
        res.send "`#{res.match[0]}` failed: #{error}"
      else
        digestRequest.id = getNextId robot
        digestRequest.room = res.envelope.room
        digestRequest.requestedBy = res.envelope.user
        digestRequest.scheduleFrequency = cron or null
        scheduleDigest robot, github, res, digestRequest, (error) ->
          if error?
            res.send "`#{res.match[0]}` failed: #{error}"
          else
            res.reply "Great! This request will show you #{digestRequest.description()}"

  robot.respond /show( all)? prs? sub(?:scriptions?)?/i, (res) ->
    responses = []
    shouldShowAll = res.match[1]?
    subscriptions = getSubscriptions robot
    subscriptions.forEach (sub) ->
      if sub.room == res.envelope.room or shouldShowAll
        if shouldShowAll
          responses.push "#{sub.room}\t#{sub.id}\t#{sub.requestedBy.name}\t#{sub.shortDescription()}"
        else
          responses.push "#{sub.id}\t#{sub.requestedBy.name}\t#{sub.shortDescription()}"

    if responses.length > 0
      if shouldShowAll
        header = "Room\tID\tRequestor\tDescription"
      else
        header = "ID\tRequestor\tDescription"
      joinedResponses = responses.join("\n")
      res.send "#{header}\n#{joinedResponses}"
    else
      res.send "No subscriptions so far. Use `#{robot.name} subscribe prs` to subscribe for all prs in this room";

  robot.respond /unsub(?:scribe)? prs? ([0-9]+)/i, (res) ->
    id = parseInt(res.match[1], 10)
    subscriptions = getSubscriptions robot
    if id != NaN
      matchingIndex = subscriptions.findIndex (digestRequest) ->
        digestRequest.id == id
      if matchingIndex >= 0
        matchingRequest = subscriptions[matchingIndex]
        if matchingRequest.room == res.envelope.room
          matchingRequest.scheduledJob.cancel()
          subscriptions.splice(matchingIndex, 1)
          res.send "Successfully unsubscribed from #{matchingRequest.id}: #{matchingRequest.description()}"
        else
          res.send "Subscription #{matchingRequest.id} is for room ##{matchingRequest.room}. You need to be in that room to unsubscribe to that report."
      else
        res.send "No subscription found for id `#{id}`. Try `#{robot.name} list pr subscriptions` to see subscriptions in this room"
    else
      res.send "#{res.match[1]} is an invalid subscription id. Try `#{robot.name} list pr subscriptions` to see subscriptions in this room"

  #
  # This is interesting. We can't store & load the response object. We need to see it again.
  # So, this little bit listens for whatever rooms it can hear and tries to resubscribe them.
  # It short-circuits if it's already seen this room before, but I'd love to actually remove this callback
  # once all the rooms in the subscriptions list have been seen.
  #
  robot.hear /.*/i, (res) ->
    resubscribeRoom robot, github, res.envelope.room, res
