express = require 'express'
namespace = require "express-namespace"
http = require "http"
fs = require "fs"
mongoose = require 'mongoose'

passport = require 'passport'
LocalStrategy = require("passport-local").Strategy
flash = require 'connect-flash'
nodemailer = require 'nodemailer'

fs = require 'fs'

root = "/api"
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

urlapipath = if !debug then "https://desk.holalabs.com"+root else "http://localhost:2222"+root
urlstorepath = if !debug then "https://desk.holalabs.com/store" else "http://localhost:2222/store"

localpath = if fs.existsSync("/home/albertoelias") then "/home/albertoelias" else "/home/test"
serverpath = if debug then localpath else "/home/holalabs"

passport.serializeUser (user, done) ->
	done null, user.id

passport.deserializeUser (id, done) ->
	dataprovider.findUserById id, (err, user) ->
    	done err, user

app = express()
app.configure ->
	app.use express.cookieParser("IDontKnowWhyThisIsASecret")
	app.use express.bodyParser()
	app.use express.methodOverride()
	app.use express.session()
	app.use flash()
	app.use passport.initialize()
	app.use passport.session()
	app.basepath = root
	app.use app.router

app.settings.mongoUrl = "mongodb://localhost/on"

app.namespace root, ->

	addHeaders = (req, res, next) ->
		res.header 'Access-Control-Allow-Headers', '*'
		next()

	app.post '/login', (req, res, next) ->
		message = {success: false}
		(passport.authenticate 'local', (err, user, info) ->
			if err or !user
				message.error = err or info.message
				return res.send 200, JSON.stringify message
			req.login user, (err) ->
				if err
					message.error = err
				else
					message.success = true
					message.user = JSON.stringify user
				return res.send 200, JSON.stringify message
		)(req, res, next)

	app.post '/register', (req, res) ->
		message = {success: false}
		dataprovider.saveUser req.body.email, req.body.username, req.body.password, (err, user) ->
			if !err
				emailBody = fs.readFileSync serverpath+"/on/desk/public/confirmemail.html", "utf8"
				emailBodyPlain = "Hi "+user.username+",\n Thanks for signing up to holadesk. Go to the URL bellow to confirm your email.\nConfirm!: $CONFIRMURL"

				smtpTransport = nodemailer.createTransport "SMTP",
					service: "Gmail"
					auth:
						user: ""
						pass: ""

				hashUrl = urlstorepath+"/confirm/"+encodeURIComponent user.hash
				mailOptions =
					from: "holadesk <no-reply@holalabs.com>"
					to: req.body.email
					subject: "Confirm your holadesk account"
					text: emailBodyPlain.replace "$CONFIRMURL", hashUrl
					html: emailBody.replace "$CONFIRMURL", hashUrl

				smtpTransport.sendMail mailOptions, (error, response) ->
					if error
						message.error = error
						res.send 200, JSON.stringify message
					else
						message.success = true
						res.send 200, JSON.stringify message
					smtpTransport.close()
			else
				message.error = err
				return res.send 200, JSON.stringify message

	app.get '/emailconfirmed', (req, res) ->
		message = {success: false}
		dataprovider.findUserByUsername req.query.username, (user) ->
			if !user
				dataprovider.findUserByEmail req.query.username, (user2) ->
					if !user2
						return res.send 200, JSON.stringify message
					if user2.emailConfirmed
						message.success = true
						return res.send 200, JSON.stringify message
					else
						return res.send 200, JSON.stringify message
			if user.emailConfirmed
				message.success = true
				return res.send 200, JSON.stringify message
			else
				return res.send 200, JSON.stringify message

	app.post '/account', (req, res) ->
		message = {success: false}
		user = email: req.body.email, username: req.body.username, password1: req.body.password1, password2: req.body.password2
		dataprovider.updateUser user, (err) ->
			if !err
				message.success = true
				return res.send 200, JSON.stringify message
			else
				message.error = err
				return res.send 200, JSON.stringify message

	app.get "/data", (req, res) ->
		message = {success: false}
		dataprovider.getUserData req.query.username, req.query.password, (err, data) ->
			if !err
				message.success = true
				message.data = data
				return res.send 200, JSON.stringify message
			else
				message.error = err
				return res.send 200, JSON.stringify message

	app.post "/data", (req, res) ->
		message = {success: false}
		dataprovider.setUserData req.body.username, req.body.password, req.body.data, (err) ->
			if !err
				message.success = true
				return res.send 200, JSON.stringify message
			else
				message.error = err
				return res.send 200, JSON.stringify message

if !debug
	server = app.listen 1718
	server.listen 1718, ->
		console.log "Listening on port " + server.address().port
else 
	server = app.listen 2223
	server.listen 2223, ->
		console.log "Listening on port " +server.address().port
