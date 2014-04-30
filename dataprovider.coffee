mongoose = require "mongoose"
Schema = mongoose.Schema
ObjectId = Schema.ObjectId  
MailChimpAPI = require("mailchimp").MailChimpAPI
bcrypt = require "bcrypt"

passport = require 'passport'
LocalStrategy = require("passport-local").Strategy

AppSchema = new Schema
  id: type: String, unique: true
  url: String
  exturl: String

  name: String
  developer: ObjectId
  description: String
  version: String

  social: Boolean
  expand: String
  permissions: Array

  height: String
  color: String
  background: String

  category: type: ObjectId
  tags: Array
  installs: Number
  published: type: Boolean, default: false

CategorySchema = new Schema
  name: String

UserSchema = new Schema
  email: type: String, unique: true
  username: type: String, unique: true
  hash: type: String, required: true
  salt: type: String, required: true
  emailConfirmed: Boolean, default: false

  developer: type: Boolean, default: false
  developername: String
  apps: Array

  subscription: Number
  recurringPaymentID: type: String
  promo: String

  syncedDevices: Number
  data: type: String, default: ""

mongoose.model "User", UserSchema
mongoose.model "App", AppSchema
mongoose.model "Category", CategorySchema

db = mongoose.connect "mongodb://localhost/on"

User = mongoose.model "User"
App = mongoose.model "App"
Category = mongoose.model "Category"

mailchimp = new MailChimpAPI "ae7e48c49353303017dd2b7719b89f90-us2", { version : '1.3', secure : true }

passport.use new LocalStrategy {usernameField: 'username', passwordField: 'password'}, (username, password, done) ->
  findUserByUsername username, (user) ->
    if !user
      findUserByEmail username, (user2) ->
        if !user2
          return done null, false, message: 'Unkown username or email'
        verifyUserPassword user2, password, (verified) ->
          if !verified
            return done null, false, message: "Invalid password"
          else
            return done null, user2
    verifyUserPassword user, password, (verified) ->
      if !verified
        return done null, false, message: "Invalid password"
      else
        return done null, user

DataProvider = ->

# User stuff
DataProvider.prototype.userInfo = (req, callback) ->
  if req.loggedIn
    callback()

DataProvider.prototype.findAllUsers = (callback) ->
  User.find {}, (err, users) ->
    callback null, users

DataProvider.prototype.findUserById = (id, callback) ->
  User.findById id, (err, user) ->
    callback err, user

findUserByEmail = (email, callback) ->
  User.findOne email: email, (err, user) ->
    if !err
      callback user
    else
      callback err

findUserByUsername = (username, callback) ->
  regex = new RegExp(["^",username,"$"].join(""),"i")
  User.findOne username: regex, (err, user) ->
    if !err
      callback user
    else
      callback err

DataProvider.prototype.modifyUserById = (id, consoleallback) ->
  User.findById id, (err, user) ->
    if !err
      user.save (err) ->
        callback()

DataProvider.prototype.deleteUserById = (id, callback) ->
  User.findById id, (err, user) ->
    if !err
      user.remove (err) ->
        callback()

DataProvider.prototype.save = (user, callback) -> 
  user.save (err) ->
    callback err

verifyRegisteringUser = (email, username, callback) ->
  if !/^[\w ]+[._\-’'‘]?[\w ]*$/.test username
    error = "Your username " + username + " can't contain spaces or non-alphanumeric characters except [._-'] between alphanumeric characters."
    callback error
  else
    findUserByUsername username, (user) ->
      if user isnt null
        error = "Your username " + username + " has already been taken."
        callback error
      else
        findUserByEmail email, (user2) ->
          if user2 isnt null
            error = "Your email " + email + " has already been taken."
            callback error
          else
            callback true

DataProvider.prototype.confirmEmail = (hash, callback) ->
  User.findOne hash: hash, (err, user) ->
    if user
      user.emailConfirmed = true
      user.save (err) ->
        callback err, true
    else
      err = if !err then "User not found, please report to hola@holalabs.com" else err
      callback err, false

DataProvider.prototype.saveUser = (email, username, password, callback) ->
  verifyRegisteringUser email, username, (cb) ->
    if cb is true
      salt = bcrypt.genSaltSync 10
      hash = bcrypt.hashSync password, salt
      user = new User email: email, username: username, hash: hash, salt: salt
      user.save (err) ->
        if !err
          findUserByEmail email, (user) ->
            callback null, user
        else
          callback err, null
    else
      callback cb, null

DataProvider.prototype.updateUser = (user, callback) ->
  findUserByEmail user.email, (user2) ->
    if user2 isnt null
      if typeof user.username isnt "undefined"  and user.username isnt ""
        findUserByUsername user.username, (user3) ->
          if user3 isnt null and user.username is user3.usernameuser2.developer
            callback "Your username " + user.username + " has already been taken."
          else if user2.developer
            callback "Developers can\'t change their usernames. We hope to implement this in the future."
          else 
            verifyUserPassword user2, user.password1, (res) ->
              if res
                user2.username = user.username
                if typeof user.password2 isnt "undefined" and user.password2 isnt ""
                  salt = bcrypt.genSaltSync 10
                  hash = bcrypt.hashSync user.password2, salt
                  user2.hash = hash
                  user2.salt = salt
                  user2.save (err) ->
                    callback err
                else
                  user2.save (err) ->
                    callback err
              else
                callback "You didn\'t  introduce the correct password."

      else if typeof user.password2 isnt "undefined" and user.password2 isnt ""
        verifyUserPassword user2, user.password1, (res) ->
          if res
            salt = bcrypt.genSaltSync 10
            hash = bcrypt.hashSync user.password2, salt
            user2.hash = hash
            user2.salt = salt
            user2.save (err) ->
              callback err
          else
            callback "You didn\'t introduce the correct password."
      else
        callback "You didn\'t introduce anything."
    else
      callback "Your email " + user.email + " isn\'t registered."

DataProvider.prototype.getUserData = (username, password, callback) ->
  findUserByUsername username, (user) ->
    if user isnt null
      verifyUserPassword user, password, (res) ->
        if res
          if typeof user.data is 'undefined'
            user.data = ""
          callback null, user.data
        else
          callback "Your password isn\'t correct.", null
    else
      callback "Your username isn\'t correct.", null

DataProvider.prototype.setUserData = (username, password, data, callback) ->
  findUserByUsername username, (user) ->
    if user isnt null
      verifyUserPassword user, password, (res) ->
        if res
          user.data = data
          user.save (err) ->
            callback err
        else
          callback "Your password isn\'t correct.", null
    else
      callback "Your username isn\'t correct.", null

verifyUserPassword = (user, password, callback) ->
  bcrypt.compare password, user.hash, (err, res) ->
    callback res

# Developer specific methods
DataProvider.prototype.isDev = (id, callback) ->
  User.findById id, (err, user) ->
    if err
      callback err
    else
      callback user.developer

DataProvider.prototype.setAsDev = (id, devName, callback) ->
  User.findById id, (err, user) ->
    if err
      callback err
    else
      regex = new RegExp(["^",devName,"$"].join(""),"i")
      User.findOne developername: regex, (e, user2) ->
        if !user2
          user.developer = true
          user.developername = devName
          user.save (er) ->
            callback er
        else
          callback "That developer name is already being used."

DataProvider.prototype.getAppsByDev = (id, callback) ->
  App.find developer: id, (err, apps) ->
    if err
      callback err
    else
      callback apps
# Apps related stuff
DataProvider.prototype.findApp = (id, callback) ->
  App.findOne id: id, (err, app) ->
    if err
      callback err
    else
      callback app

DataProvider.prototype.findPublishedApps = (callback) ->
  App.find published: true, (err, apps) ->
    callback apps

DataProvider.prototype.findAppsByCategory = (category, callback) ->
  App.find {category: category, published: true}, (err, apps) ->
    if err
      callback err
    else
      callback apps
    
DataProvider.prototype.findAppById = (id, callback) ->
  App.findById id, (err, app) ->
      callback err, app

DataProvider.prototype.saveApp = (appid, url, name, description, version, social, permissions, expand, height, color, background, external_url, callback) ->
  App.findOne id: appid, (errr, app) ->
    if !app
      username = appid.split ".", 1
      User.findOne username:username[0], (er, user) ->
        if !er
          app = new App id: appid, url: url, name: name, developer: user._id, description: description, version: version, social: social, permissions: permissions, expand: expand, height: height, color: color, background: background, exturl: external_url
          nameTags = name.toLowerCase().split " "
          descTags = description.toLowerCase().split " "
          app.tags =  nameTags.concat descTags
          app.save (err) ->
            if !err
              applist = user.apps
              applist.push appid
              user.apps = applist 
              user.save (e) ->
                callback e
            else
              callback err
        else
          callback er 
    else
      callback "That app has already been uploaded. If you want to update it go to it's page."

DataProvider.prototype.uploadUpdateApp = (id, url, appid, name, description, version, social, permissions, expand, height, color, background, external_url, category, published, callback) ->
  App.findById id, (errr, app) ->
    if !errr
      if appid is app.id
        oldI = app.version.indexOf "."
        newI = version.indexOf "."
        oldVersion = app.version.replace /[.]/g, ""
        newVersion = version.replace /[.]/g, ""
        app.version = oldVersion.substr(0, oldI) + "." + oldVersion.substr oldI
        version = newVersion.substr(0, newI) + "." + newVersion.substr newI
        if parseFloat(version) > parseFloat(app.version)
          app.url = url
          app.name = name
          app.description = description
          app.version = version
          app.social = social
          app.permissions = permissions
          app.expand = expand
          app.height = height
          app.color = color
          app.background = background
          app.exturl = external_url
          app.category = category
          app.published = published
          nameTags = name.toLowerCase().split " "
          descTags = description.toLowerCase().split " "
          app.tags =  nameTags.concat descTags
          app.save (err) ->
            callback err
        else
          callback "Your updated app must have a higher version number than the previous one."
      else
        callback "The app you uploaded doesn\'t have the same id as the app you\'re trying to update. You can\'t change the id of an app."
    else
      callback errr

DataProvider.prototype.updateApp = (id, category, published, callback) ->
  App.findById id, (errr, app) ->
    if !errr
      app.category = category
      app.published = published
      app.save (err) ->
        callback err
    else
      callback errr

DataProvider.prototype.searchAppNames = (searchTerm, num1, num2, callback) ->
  searchTerm = searchTerm.toLowerCase()
  App.where('tags').all(searchTerm.split " ")
    .sort('-name')
    .skip(num1)
    .limit(num2)
    .exec (err, apps) ->
      callback err, apps


DataProvider.prototype.removeApp = (id, callback) ->
  App.findById id, (err, app) ->
    if !err
      User.findById app.developer, (errr, user) ->
        apps = user.apps
        i = apps.indexOf app.id
        apps.splice i,1
        user.apps = apps
        user.save (er) ->
          if !er
            app.remove (e) ->
              callback e
          else
            callback er
    else
      callback err

DataProvider.prototype.addInstall = (id, callback) ->
  App.findAppById id, (err, app) ->
    if !err
      app.installs++
      app.save (er) ->
        callback er
    else
      callback err

# Categories
DataProvider.prototype.setCategory = (name, callback) ->
  category = new Category name: name
  category.save (err) ->
    callback err

DataProvider.prototype.findCategoryById = (id, callback) ->
  Category.findById id, (err, category) ->
    if !err
      callback category
    else
      callback err

DataProvider.prototype.findCategoryByName = (name, callback) ->
  Category.findOne name: name, (err, category) ->
    if !err
      callback category
    else
      callback err

DataProvider.prototype.findCategories = (callback) ->
  Category.find {}, (err, categories) ->
    callback categories

DataProvider.prototype.findUserByUsername = findUserByUsername
DataProvider.prototype.findUserByEmail = findUserByEmail

exports.DataProvider = DataProvider
