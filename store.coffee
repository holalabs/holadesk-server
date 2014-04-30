express = require 'express'
namespace = require "express-namespace"
http = require "http"
https = require "https"
mongoose = require 'mongoose'

passport = require 'passport'
LocalStrategy = require("passport-local").Strategy
flash = require 'connect-flash'
nodemailer = require "nodemailer"

fs = require "fs"
jade = require "jade"
admzip = require "adm-zip"
bcrypt = require "bcrypt"
root = "/store"
DataProvider = require("./dataprovider").DataProvider
dataprovider = new DataProvider()

process.on "uncaughtException", (err) ->
	if !debug
		console.log "store " + err
		console.log "Node NOT Exiting..."

debug = false
debugFlag = process.argv[2]

if typeof debugFlag isnt 'undefined' and debugFlag is 'debug'
	debug = true
	path = ""

urlpath = if !debug then "https://desk.holalabs.com"+root else "http://localhost:2222"+root
localpath = if fs.existsSync("/home/albertoelias") then "/home/albertoelias" else "/home/test"
serverpath = if debug then localpath else "/home/holalabs"

ensureAuthenticated = (req, res, next) ->
	if req.isAuthenticated() 
		return next()
	res.redirect root+'/admin'

addHeaders = (req, res, next) ->
		res.header 'Access-Control-Allow-Headers', '*'
		next()

passport.serializeUser (user, done) ->
	done null, user.id

passport.deserializeUser (id, done) ->
	dataprovider.findUserById id, (err, user) ->
		done err, user

app = express()
app.configure ->
	app.set "views", __dirname + "/views"
	app.set "view engine", "jade"
	app.use express.cookieParser "IDontKnowWhyThisIsASecret"
	app.use express.bodyParser()
	app.use express.methodOverride()
	app.use express.session()
	app.use flash()
	app.use passport.initialize()
	app.use passport.session()
	app.basepath = root
	app.use root, express.static(__dirname + "/public")
	app.use app.router
	app.use express.favicon(__dirname + "/public/holadesk_favicon.png")

app.settings.mongoUrl = "mongodb://localhost/on"

app.namespace root, ->	

	app.get '/categories', (req, res) ->
		dataprovider.setCategory "Business", (err) -> console.log err
		dataprovider.setCategory "Education", (err) -> console.log err
		dataprovider.setCategory "Entertainment", (err) -> console.log err
		dataprovider.setCategory "Games", (err) -> console.log err
		dataprovider.setCategory "Multimedia", (err) -> console.log err
		dataprovider.setCategory "Social", (err) -> console.log err
		dataprovider.setCategory "Tools and utilities", (err) -> console.log err

	app.get '/admin', (req, res) ->
		if req.isAuthenticated()
			dataprovider.findUserById req.user._id, (err, user) ->
				if user.emailConfirmed
					dataprovider.isDev req.user._id, (bool) ->
						if !bool
							res.redirect root+'/admin/signup'
						else
							dataprovider.getAppsByDev req.user._id, (apps) ->
								if typeof apps[0] is "undefined"
									apps[0] = {name: "Start uploading now!"}
								errors = if typeof req.query.error isnt "undefined" then req.query.error.split "," else ""
								res.render 'admin'
									user: req.user
									apps: apps
									errors: errors
				else
					res.redirect root+'/confirm'
		else
			res.render 'admin'
				user: req.user

	checkInputs = (url, callback) ->
		if url.length is 0 or url.slice(url.lastIndexOf(".")) isnt ".webapp" or url.slice(0, 4) isnt "http" 
			callback "You need to specify the url with the path to your application manifest: https://myapp.com/mymanifest.webapp"
			return
		callback null

	readURL = (appurl, id, callback) ->
		err = []
		urlNoProtocol = appurl.slice(appurl.indexOf("//")+2)
		urlindex = urlNoProtocol.indexOf("/")
		host = urlNoProtocol.slice 0, urlindex
		path = urlNoProtocol.slice urlindex
		options = {
				host: host
				path: path
			}
		protocol = appurl.slice(0, appurl.indexOf("://"))
		if protocol is "https"
			options.port = 443
		prot = if options.port is 443 then https else http
		req = prot.request options, (res) ->
			output = ''
			res.setEncoding 'utf8'

			res.on 'data', (chunk) ->
				output += chunk

			res.on 'end', ->
				if output is ""
					err.push 'You need to specify the url with the path to your application manifest: https://myapp.com/mymanifest.webapp'
					callback err, null, null, null, null, null, null, null, null, null, null, null, null
					return
				else
					try
						manifestjson = JSON.parse output
					catch error
						err.push "Your application manifest isn't formated correctly."
						callback err, null, null, null, null, null, null, null, null, null, null, null, null
						return

					#App Name
					if typeof manifestjson.name is "undefined" or manifestjson.name.trim() is ""
						err.push 'You have to fill in the name of your app in your manifest.json.'
					else
						name = manifestjson.name.trim()
					
					#App ID
					if typeof manifestjson.id is "undefined" or manifestjson.id.trim() is ""
						err.push 'You have to specify an id for your app in your manifest.json and it can\'t contain spaces or non-alphanumeric characters.'
					else
						if /\w/g.test manifestjson.id.trim()
							appid = manifestjson.id.trim()

					#App Description
					if typeof manifestjson.description is "undefined" or manifestjson.description.trim() is ""
						err.push 'You have to fill in the description of your app in your manifest.json.'
					else
						desc = manifestjson.description.trim()
					
					#App Version
					if typeof manifestjson.version is "undefined" or manifestjson.version.trim() is ""
						err.push 'You have to the indicate the version of your app in your manifest.json.'
					else
						version = manifestjson.version.trim()

					#App External URL
					if typeof manifestjson.external_url is "undefined"
						external_url = ""
					else
						external_url = manifestjson.external_url.trim()

					#App Expand
					if typeof manifestjson.expand is "undefined"
						expand = ""
					else
						expand = manifestjson.expand.trim()

					#App Height
					if typeof manifestjson.height is "undefined"
						height = ""
					else
						height = manifestjson.height.trim()

					#App Color
					if typeof manifestjson.color is "undefined"
						color = ""
					else
						color = manifestjson.color.trim()

					#App Background
					if typeof manifestjson.background is "undefined"
						background = ""
					else
						background = manifestjson.background.trim()

					#App Social
					if typeof manifestjson.social is "undefined"
						social = false
					else
						social = manifestjson.social

					permissions = manifestjson.permissions
					dataprovider.findUserById id, (errr, user) ->
						#App developer
						if typeof manifestjson.developer.name is "undefined" or manifestjson.developer.name.trim() is "" or manifestjson.developer.name isnt user.developername
							err.push 'You have to the indicate your developer name in the developer key in the manifest.json.'

						uniqueappid = user.username + "." + appid
						if typeof err[0] is "undefined"
							err = null
						callback err, uniqueappid, appurl, name, desc, version, social, permissions, expand, height, color, background, external_url

		req.on 'error', (errr) ->
			err.push "You need to specify the url with the path to your application manifest: https://myapp.com/mymanifest.webapp"
			callback err, null, null, null, null, null, null, null, null, null, null, null, null
			
		req.end()

	saveApp = (uniqueappid, url, name, desc, version, social, permissions, expand, height, color, background, external_url, callback) ->
		err = []
		dataprovider.saveApp uniqueappid, url, name, desc, version, social, permissions, expand, height, color, background, external_url,(errr) ->
			if !errr
				callback null, uniqueappid
			else
				err.push errr
				callback err, null

	app.post '/admin', (req, res) ->
		url = req.body.urlupload.trim().replace /\s{1,}/g, ''
		checkInputs url, (errr) ->
			if !errr
				readURL url, req.user._id, (err, uniqueappid, url, name, desc, version, social, permissions, expand, height, color, background, external_url) ->
					if !err
						saveApp uniqueappid, url, name, desc, version, social, permissions, expand, height, color, background, external_url, (err, uniqueappid) ->
							if !err
								dataprovider.findApp uniqueappid, (app) ->
									res.redirect root+"/admin/app/"+app._id
							else
								res.redirect root+'/admin?error='+err
					else
						res.redirect root+'/admin?error='+err
			else
				res.redirect root+'/admin?error='+errr

	app.get '/admin/signup', [ensureAuthenticated], (req, res) ->
		dataprovider.findUserById req.user._id, (err, user) ->
			if user.emailConfirmed
				dataprovider.isDev req.user._id, (bool) ->
					if !bool
						error = if typeof req.query.error isnt "undefined" then req.query.error else ""
						res.render "devsignup"
							user: req.user
							error: error
					else
						res.redirect root+'/admin'
			else
				res.redirect root+'/confirm'

	app.post '/admin/signup', (req, res) ->
		devname = req.body.devname.trim().replace(/\s{2,}/g, ' ')
		if req.body.tos isnt "on"
			res.redirect root+'/admin/signup?error=You have to accept signing up as a developer.'
		if devname.length <= 0 or devname.length > 20
			res.redirect root+'/admin/signup?error=You have to introduce a name that not only contains whitespaces and it can\'t have more than 20 characters.'
		dataprovider.setAsDev req.user._id, devname, (err) ->
			if !err
				res.redirect root+'/admin'
			else
				res.redirect root+'/admin/signup?error='+err

	uploadUpdateApp = (id, url, uniqueappid, name, desc, version, social, permissions, expand, height, color, background, external_url, category, published, callback) ->
		err = []
		dataprovider.uploadUpdateApp id, url, uniqueappid, name, desc, version, social, permissions, expand, height, color, background, external_url, category, published, (errr) ->
			if !errr
				callback null
			else
				err.push errr
				callback err

	app.get '/admin/app/:id', ensureAuthenticated, (req, res) ->
		dataprovider.findUserById req.user._id, (err, user) ->
			if user.emailConfirmed
				dataprovider.findAppById  req.params.id, (err, app) ->
					dataprovider.findCategories (categories) ->
						errors = if typeof req.query.error isnt "undefined" then req.query.error.split "," else ""
						res.render 'adminappview'
							urlpath: urlpath
							user: req.user
							app: app
							categories: categories
							errors: errors
			else
				res.redirect root+'/confirm'

	app.post '/admin/app/:id', (req, res) ->
		published = if typeof req.body.published is "undefined" then false else true
		updatemanifest = if typeof req.body.updatemanifest is "undefined" then false else true

		url = req.body.urlupload.trim().replace /\s{1,}/g, ''
		if updatemanifest
			checkInputs url, (errr) ->
				if !errr
					readURL url, req.user._id, (err, uniqueappid, appurl, name, desc, version, social, permissions, expand, height, color, background, external_url) ->		
						console.log "María es preciosa y por eso sale aquí"
						if !err
							uploadUpdateApp req.params.id, url, uniqueappid, name, desc, version, social, permissions, expand, height, color, background, external_url, req.body.category, published, (er) ->
								if !er
									res.redirect root+"/admin/app/"+req.params.id
								else
									res.redirect root+'/admin/app/'+req.params.id+'?error='+er
						else
							res.redirect root+'/admin/app/'+req.params.id+'?error='+err
				else
					res.redirect root+'/admin/app/'+req.params.id+'?error='+errr
		else
			dataprovider.updateApp req.params.id, req.body.category, published, (err) ->
				if !err
					res.redirect root+"/admin/app/"+req.params.id
				else
					res.redirect root+'/admin/app/'+req.params.id+'?error='+err

	app.delete '/admin/app/:id', (req, res) ->
		dataprovider.findAppById req.params.id, (err, app) ->
			if !err
				dataprovider.removeApp req.params.id, (err) ->
					res.contentType "application/json"
					data = urlpath+'/admin'
					res.header 'Content-Length', data.length
					res.end data
			else
				res.contentType "application/json"
				data = urlpath+'/admin?error=Application couldn\'t be deleted correctly because of '+err+'.'
				res.header 'Content-Length', data.length
				res.end data

#---------------------------------
# User Store
#---------------------------------

	app.get '/', (req, res) ->
		dataprovider.findPublishedApps (apps) ->
			dataprovider.findCategories (categories) ->
				res.render 'store'
					apps: apps
					categories: categories

	app.get '/app/:id', (req, res) ->
		id = req.params.id
		dataprovider.findApp id, (app) ->
			dataprovider.findUserById app.developer, (err, developer) ->
				if typeof req.query.endpoint is "undefined"
					dataprovider.findCategories (categories) ->
						url = app.url.slice(0, app.url.lastIndexOf("/manifest.webapp"))
						res.render 'appview'
							categories: categories,
							app: app,
							dev: developer.developername,
							url: url,
							sharetext: encodeURIComponent(app.name + " for holadesk "),
							sharelink: encodeURIComponent("https://desk.holalabs.com/store/app/"+id+"/")
				else
					app.developer = developer.developername
					res.send 200, JSON.stringify app

	app.get '/category/:name', (req, res) ->
		dataprovider.findCategoryByName req.params.name, (category) ->
			dataprovider.findAppsByCategory category._id, (apps) ->
				dataprovider.findCategories (categories) ->
					res.render 'store'
						apps: apps
						categories: categories

	app.get '/search/:searchterm/:num1/:num2', addHeaders, (req, res) ->
		serchterm = req.params.searchterm
		num1 = req.params.num1
		num2 = req.params.num2
		dataprovider.searchAppNames req.params.searchterm, req.params.num1, req.params.num2, (err, apps) ->
			dataprovider.findCategories (categories) ->
					res.render 'store'
						apps: apps
						categories: categories
						search: req.params.searchterm

	app.get '/search', addHeaders, (req, res) ->
		searchterm = req.query.q
		dataprovider.searchAppNames searchterm, 0, 50, (err, apps) ->
			dataprovider.findCategories (categories) ->
					res.render 'store'
						apps: apps
						categories: categories
						search: searchterm

	app.post '/update', addHeaders, (req, res) ->
		appids = req.body.apps.split(",")
		message = {}
		count = 0
		for id in appids then do (id) ->
			dataprovider.findApp id, (app) ->
				count++
				message[id] = app.version
				if count is appids.length
					return res.send 200, JSON.stringify message

	app.get '/login', (req, res) ->
		if !req.isAuthenticated()
			error = req.flash 'error'
			res.render 'login'
				user: req.user
				message: error[0]
		else
			res.redirect root+'/admin'

	app.post '/login', passport.authenticate 'local', {failureRedirect: root+'/login', successRedirect: root+'/admin', failureFlash: true}

	app.get '/logout', (req, res) ->
		req.logout()
		res.redirect root+'/admin'

	app.get "/forgot", (req, res) ->
		if !req.isAuthenticated()
			errors = if typeof req.query.error isnt "undefined" then req.query.error.split "," else ""
			sent = if typeof req.query.sent isnt "undefined" then req.query.sent else false
			res.render "forgot"
				user: req.user
				sent: sent
				errors: errors
		else
			res.redirect root+'/login'

	random = `function () {
		var chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890";
		var string = "";
		for (i=0; i<8; i++) {
			var rnum = Math.floor(Math.random() * chars.length);
			string += chars.substring(rnum, rnum+1);
		}
		return string;
		}`

	app.post "/forgot", addHeaders, (req, res) ->
		email = req.body.email
		dataprovider.findUserByEmail email, (user) ->
			message = {success: false}
			if user != null
				if user.emailConfirmed
					password = random()

					salt = bcrypt.genSaltSync 10
					hash = bcrypt.hashSync password, salt
					user.salt = salt
					user.hash = hash

					dataprovider.save user, (err) ->
						if err
							console.log err
						else
							emailBody = fs.readFileSync serverpath+"/on/desk/public/forgotemail.html", "utf8"
							emailBodyPlain = "Hi "+user.username+",\nWe were told that you forgot your password, so here's your new one:\n $PASSWORD\nLog in: http://desk.holalabs.com/desk"

							smtpTransport = nodemailer.createTransport "SMTP", {
									service: "Gmail"
									auth: {
										user: ""
										pass: "" }
								}

							mailOptions = 
								{
									from: "holadesk <no-reply@holalabs.com>"
									to: email
									subject: "Your new holadesk password"
									text: emailBodyPlain.replace "$PASSWORD", password
									html: emailBody.replace "$PASSWORD", password
								}

							smtpTransport.sendMail mailOptions, (error, response) ->
								if error
									if typeof req.body.endpoint is "undefined"
										res.redirect root+'/forgot?error='+error
									else
										message.error = error
										res.send 200, JSON.stringify message
								else
									if typeof req.body.endpoint is "undefined"
										res.redirect root+'/forgot?sent='+true
									else
										message.success = true
										message.username = user.username
										res.send 200, JSON.stringify message

								smtpTransport.close()
				else
					if typeof req.body.endpoint is "undefined"
						res.redirect root+"/confirm"
					else
						message.error = "Your email hasn\'t been confirmed yet. Please look for your confirmation email in your inbox."
						return res.send 200, JSON.stringify message
			else
				error = email + " isn't in our database"
				if typeof req.body.endpoint is "undefined"
					res.redirect root+'/forgot?error='+error
				else
					message.error = error
					return res.send 200, JSON.stringify message


	app.get "/confirm", (req, res) ->
		if req.isAuthenticated()
			dataprovider.findUserById req.user._id, (err, user) ->
				if user.emailConfirmed
					res.redirect root+'/admin'
				else
					res.render "confirm"
						user: req.user
		else
			res.redirect root+'/login'

	app.get "/confirm/:hash", addHeaders, (req, res) ->
		hash = decodeURIComponent req.params.hash
		dataprovider.confirmEmail hash, (err, bool) ->
			if !err and bool
				res.redirect "http://desk.holalabs.com/desk"
			else
				res.render "confirm"
					errors: [err]
					user: req.user

#---------------------------------
# Store API
#---------------------------------

	app.get '/apps/list', addHeaders, (req, res) ->
		applist = ''
		dataprovider.findPublishedApps (apps) ->
			apps.forEach (app, i) ->
				if i > 0
					applist += ","
				applist += '"'+app.id+'":'+JSON.stringify app
			applist = "{"+applist+"}"
			res.end JSON.stringify apps: JSON.parse applist

	app.get '/categories', addHeaders, (req, res) ->
		dataprovider.findCategories (categories) ->
			res.end JSON.stringify categories
			
if !debug
	server = app.listen 1717
	server.listen 1717, ->
		console.log "Listening on port " + server.address().port
else 
	server = app.listen 2222
	server.listen 2222, ->
		console.log "Listening on port " +server.address().port
