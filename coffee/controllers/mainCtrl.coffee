timeTracker.controller 'MainCtrl', ($rootScope, $scope, $timeout, $location, $anchorScroll, $window, $q, Ticket, Project, Redmine, Account, State, DataAdapter, Message, Chrome, Resource, Option, Log, Analytics) ->

  DATA_SYNC = "DATA_SYNC"
  MINUTE_5 = 5
  TICKET_CLOSED = 5
  NOT_FOUND = 404
  UNAUTHORIZED = 401
  # http request canceled.
  STATUS_CANCEL = 0
  # don't use query
  QUERY_ALL_ID = 0

  # list for toast Message.
  $rootScope.messages = []

  ###
   Initialize.
  ###
  init = () ->
    deferred = $q.defer()
    deferred.promise
      .then(_initializeGoogleAnalytics)
      .then(_initializeDataFromChrome)
      .then(_initializeDataFromRedmine)
      .then(_initializeEvents)
      .then(_setDataSyncAlarms)
    deferred.resolve()

  ###
   initialize events.
  ###
  _initializeEvents = () ->
    Log.debug "start initialize Event."
    DataAdapter.addEventListener DataAdapter.ACCOUNT_ADDED, _loadRedmine
    DataAdapter.addEventListener DataAdapter.PROJECTS_CHANGED, () ->
      Project.syncLocal(DataAdapter.getProjects())
    DataAdapter.addEventListener DataAdapter.TICKETS_CHANGED, () ->
      Ticket.syncLocal(DataAdapter.tickets)
    Option.onChanged('reportUsage', (e) -> Analytics.setPermission(e) )
    Option.onChanged('hideNonTicketProject',  _toggleProjectHidden)
    Log.debug "finish initialize Event."

  ###
   load projects from redmine.
  ###
  _loadRedmine = (accounts) ->
    for a in accounts
      _loadActivities(a)
      _loadQueries(a)
      $q.all([_loadProjects(a), _loadStatuses(a)])
        .then(_loadIssues(a))
        .then(_loadIssueCount(a))

  ###
   load projects from redmine.
  ###
  _loadProjects = (a) ->
    Redmine.get(a).loadProjects(page: 1, limit: 50)
      .then(_successLoadProject, _errorLoadProject)

  ###
   load projects from redmine.
  ###
  _successLoadProject = (data, status) =>
    if data.projects?
      projects = DataAdapter.getProjects(data.url)
      data.projects.map (p) ->
        saved = projects.find (n) -> n.equals p
        return if not saved
        p.show = saved.show
        p.queryId = saved.queryId
        # On chrome, project doesn't have text. Update it here.
        if p.equals DataAdapter.selectedProject
          DataAdapter.selectedProject.text = p.text
      DataAdapter.addProjects(data.projects)
      Message.toast Resource.string("msgLoadProjectSuccess").format(data.account.name), 2000
    else
      _errorLoadProject data

  ###
   show error message.
  ###
  _errorLoadProject = (data, status) =>
    if status is STATUS_CANCEL then return
    Log.debug("_errorLoadProjects() start")
    Message.toast Resource.string("msgLoadProjectFail").format(data.account.name), 3000

  ###
   load activities for account.
   @param account {AccountModel} - load from this account.
  ###
  _loadActivities = (account) ->
    Redmine.get(account).loadActivities()
      .then((data) ->
        if not data?.time_entry_activities? then return
        Log.info "Redmine.loadActivities success"
        DataAdapter.setActivities(data.url, data.time_entry_activities))

  ###
   load queries for account.
   @param account {AccountModel} - load from this account.
  ###
  _loadQueries = (account) ->
    params =
      page: 1
      limit: 50
    Redmine.get(account).loadQueries(params)
      .then((data) ->
        data.queries.add({id: QUERY_ALL_ID, name: 'All'}, 0)
        DataAdapter.setQueries(data.url, data.queries)
      , (data, status) =>
        if status is STATUS_CANCEL then return
        Message.toast Resource.string("msgLoadQueryFail").format(data.account.name), 2000)

  ###
   load statuses for account.
   @param account {AccountModel} - load from this account.
  ###
  _loadStatuses = (account) =>
    Redmine.get(account).loadStatuses()
      .then((data) ->
        DataAdapter.setStatuses(data.url, data.issue_statuses)
      , (data, status) ->
        if status is STATUS_CANCEL then return
        Message.toast(Resource.string("msgLoadStatusesFail").format(data.account.name), 2000))

  ###
   load issues for account.
   @param account {AccountModel} - load from this account.
  ###
  _loadIssues = (account) -> () ->
    for t in DataAdapter.tickets when account.url is t.url
      Redmine.get(account).getIssuesById t.id, _upsateIssue(t), _issueNotFound(account)

  ###
   when issue found, update according to it.
  ###
  _upsateIssue = (target) -> (issue) ->
    for k, v of issue then target[k] = v
    return if not Option.getOptions().removeClosedTicket
    # remove closed issues.
    statuses = DataAdapter.getStatuses(target.url)
    status = statuses.find (n) -> n.id is target.status.id
    if status?.is_closed
      DataAdapter.toggleIsTicketShow(target)
      Message.toast(Resource.string("msgIssueClosed").format(target.text), 3000)

  ###
   when issue not found, remove issue.
  ###
  _issueNotFound = (account) -> (issue, status) ->
    if status is NOT_FOUND or status is UNAUTHORIZED
      DataAdapter.toggleIsTicketShow(issue)
      Message.toast(Resource.string("msgIssueMissing").format(target.text, account.name), 3000)

  ###
   count project's issues count.
  ###
  _loadIssueCount = (account) -> () ->
    return if not Option.getOptions().hideNonTicketProject
    projects = DataAdapter.getProjects(account.url)
    promises = projects.map (p) ->
      params = limit: 1, project_id: p.id, status_id: "open"
      Redmine.get(account).getIssuesPararell(params)
        .then((d) ->
          p.ticketCount = d.total_count
          Log.debug("project: " + p.text + "\tticketCount: " + p.ticketCount))
    $q.all(promises).then(() -> DataAdapter.updateProjects())

  ###
   count project's issues count on all accounts.
  ###
  _toggleProjectHidden = (enableHide) ->
    if not enableHide
      DataAdapter.updateProjects()
    else
      for a in Account.getAccounts()
        _loadIssueCount(a)()

  ###
   request a setup of redmine account to user.
  ###
  _requestAddAccount = () ->
    $timeout () ->
      State.isAdding = true
    , 500
    $timeout () ->
      $location.hash('accounts')
      $anchorScroll()
    , 1000
    $timeout () ->
      Message.toast(Resource.string("msgRequestAddAccount_0"), 5000)
    , 1500
    $timeout () ->
      Message.toast(Resource.string("msgRequestAddAccount_1"), 5000)
    , 2500

  ###
   initialize GoogleAnalytics.
  ###
  _initializeGoogleAnalytics = () ->
    Analytics.init {
      serviceName:   "RedmineTimeTracker"
      analyticsCode: "UA-32234486-7"
    }
    Analytics.sendView("/app/")

  ###
   initialize Data from chrome storage.
  ###
  _initializeDataFromChrome = () ->
    Log.debug "start initialize data."
    Option.loadOptions()
      .then(_initializeAccount)
      .then(_initializeProject)
      .then(_initializeIssues)
      .then(() -> Log.debug "finish initialize data.")

  ###
   Initialize account from chrome storage.
  ###
  _initializeAccount = () ->
    Account.load().then (accounts) ->
      if accounts
        DataAdapter.addAccounts(accounts)
      else if not accounts[0]?
        _requestAddAccount()

  ###
   Initialize project from chrome storage.
  ###
  _initializeProject = () ->
    Project.load().then (projects) ->
      DataAdapter.addProjects(projects)

  ###
   Initialize issues status.
  ###
  _initializeIssues = () ->
    Ticket.load().then (tickets) ->
      DataAdapter.toggleIsTicketShow(tickets)

  ###
   initialize Data from Redmine.
  ###
  _initializeDataFromRedmine = () ->
    accounts = DataAdapter.getAccount()
    _loadRedmine(accounts)


  ###
   set datasync event to chrome alarms.
  ###
  _setDataSyncAlarms = () ->
    alarmInfo =
      when: Date.now() + 1
      periodInMinutes: MINUTE_5
    Chrome.alarms.create(DATA_SYNC, alarmInfo)
    Chrome.alarms.onAlarm.addListener (alarm) ->
      return if not alarm.name is DATA_SYNC
      Ticket.sync(DataAdapter.tickets)
      Project.sync(DataAdapter.getProjects())

  ###
   Start Initialize.
  ###
  init()

