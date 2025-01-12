	////////////
	//SECURITY//
	////////////
#define UPLOAD_LIMIT		10485760	//Restricts client uploads to the server to 10MB //Boosted this thing. What's the worst that can happen?
#define MIN_CLIENT_VERSION	0		//Just an ambiguously low version for now, I don't want to suddenly stop people playing.
									//I would just like the code ready should it ever need to be used.

//#define TOPIC_DEBUGGING 1

	/*
	When somebody clicks a link in game, this Topic is called first.
	It does the stuff in this proc and  then is redirected to the Topic() proc for the src=[0xWhatever]
	(if specified in the link). ie locate(hsrc).Topic()

	Such links can be spoofed.

	Because of this certain things MUST be considered whenever adding a Topic() for something:
		- Can it be fed harmful values which could cause runtimes?
		- Is the Topic call an admin-only thing?
		- If so, does it have checks to see if the person who called it (usr.client) is an admin?
		- Are the processes being called by Topic() particularly laggy?
		- If so, is there any protection against somebody spam-clicking a link?
	If you have any  questions about this stuff feel free to ask. ~Carn
	*/
/client/Topic(href, href_list, hsrc)
	if(!usr || usr != mob)	//stops us calling Topic for somebody else's client. Also helps prevent usr=null
		return

	#if defined(TOPIC_DEBUGGING)
	world << "[src]'s Topic: [href] destined for [hsrc]."

	if(href_list["nano_err"]) //nano throwing errors
		world << "## NanoUI, Subject [src]: " + html_decode(href_list["nano_err"]) //NANO DEBUG HOOK

	#endif

	//search the href for script injection
	if( findtext(href,"<script",1,0) )
		world.log << "Attempted use of scripts within a topic call, by [src]"
		message_admins("Attempted use of scripts within a topic call, by [src]")
		//del(usr)
		return

	//Admin PM
	if(href_list["priv_msg"])
		var/client/C = locate(href_list["priv_msg"])
		var/datum/ticket/ticket = locate(href_list["ticket"])
		if(ismob(C)) 		//Old stuff can feed-in mobs instead of clients
			var/mob/M = C
			C = M.client
		cmd_admin_pm(C, null, ticket)
		return

	if(href_list["irc_msg"])
		if(!holder && received_irc_pm < world.time - 6000) //Worse they can do is spam IRC for 10 minutes
			usr << "<span class='warning'>You are no longer able to use this, it's been more then 10 minutes since an admin on IRC has responded to you</span>"
			return
		if(mute_irc)
			usr << "<span class='warning'You cannot use this as your client has been muted from sending messages to the admins on IRC</span>"
			return
		cmd_admin_irc_pm(href_list["irc_msg"])
		return

	if(href_list["close_ticket"])
		var/datum/ticket/ticket = locate(href_list["close_ticket"])

		if(isnull(ticket))
			return

		ticket.close(client_repository.get_lite_client(usr.client))

	//Logs all hrefs
	if(config && config.log_hrefs && href_logfile)
		href_logfile << "<small>[time2text(world.timeofday,"hh:mm")] [src] (usr:[usr])</small> || [hsrc ? "[hsrc] " : ""][href]<br>"

	switch(href_list["_src_"])
		if("holder")	hsrc = holder
		if("usr")		hsrc = mob
		if("prefs")		return prefs.process_link(usr,href_list)
		if("vars")		return view_var_Topic(href,href_list,hsrc)

	..()	//redirect to hsrc.Topic()

//This stops files larger than UPLOAD_LIMIT being sent from client to server via input(), client.Import() etc.
/client/AllowUpload(filename, filelength)
	if(filelength > UPLOAD_LIMIT)
		src << "<font color='red'>Error: AllowUpload(): File Upload too large. Upload Limit: [UPLOAD_LIMIT/1024]KiB.</font>"
		return 0
/*	//Don't need this at the moment. But it's here if it's needed later.
	//Helps prevent multiple files being uploaded at once. Or right after eachother.
	var/time_to_wait = fileaccess_timer - world.time
	if(time_to_wait > 0)
		src << "<font color='red'>Error: AllowUpload(): Spam prevention. Please wait [round(time_to_wait/10)] seconds.</font>"
		return 0
	fileaccess_timer = world.time + FTPDELAY	*/
	return 1


	///////////
	//CONNECT//
	///////////
/client/New(TopicData)
	TopicData = null						//Prevent calls to client.Topic from connect

	if(!(connection in list("seeker", "web")))					//Invalid connection type.
		return null
	if(byond_version < MIN_CLIENT_VERSION)		//Out of date client.
		return null

	if(!config.guests_allowed && IsGuestKey(key))
		alert(src,"This server doesn't allow guest accounts to play. Please go to http://www.byond.com/ and register for a key.","Guest","OK")
		del(src)
		return

	src << "<font color='red'>If the title screen is black, resources are still downloading. Please be patient until the title screen appears.</font>"


	GLOB.clients += src
	GLOB.directory[ckey] = src

	//Admin Authorisation
	holder = admin_datums[ckey]
	if(holder)
		admins += src
		holder.owner = src

	//preferences datum - also holds some persistant data for the client (because we may as well keep these datums to a minimum)
	prefs = preferences_datums[ckey]
	if(!prefs)
		prefs = new /datum/preferences(src)
		preferences_datums[ckey] = prefs

	prefs.last_ip = address				//these are gonna be used for banning
	prefs.last_id = computer_id			//these are gonna be used for banning

	add_ip_cid_list(address, computer_id)

	if(!byond_join_date)
		byond_join_date = findJoinDate()

	prefs.byond_join_date = byond_join_date

	. = ..()	//calls mob.Login()
	prefs.sanitize_preferences()

	prefs.last_seen = full_real_time()

	if(!prefs.first_seen)
		prefs.first_seen = full_real_time()
		prefs.last_seen = full_real_time()

	if(custom_event_msg && custom_event_msg != "")
		src << "<h1 class='alert'>Custom Event</h1>"
		src << "<h2 class='alert'>A custom event is taking place. OOC Info:</h2>"
		src << "<span class='alert'>[custom_event_msg]</span>"
		src << "<br>"

	if(holder)
		add_admin_verbs()
		admin_memo_show()

	// Forcibly enable hardware-accelerated graphics, as we need them for the lighting overlays.
	// (but turn them off first, since sometimes BYOND doesn't turn them on properly otherwise)
	spawn(5) // And wait a half-second, since it sounds like you can do this too fast.
		if(src)
			winset(src, null, "command=\".configure graphics-hwmode off\"")
			sleep(2) // wait a bit more, possibly fixes hardware mode not re-activating right
			winset(src, null, "command=\".configure graphics-hwmode on\"")
	log_client_to_db()

	var/player_byond_age = get_byond_age()

	if(config.byond_antigrief_age && config.byond_antigrief_age > player_byond_age)
		log_adminwarn("Player [ckey] has joined with a newly registered byond account ([player_byond_age] days). Antigrief has been applied.")
		antigrief = TRUE

	if(config.player_antigrief_age)
		if(isnum(player_age) && (config.player_antigrief_age > player_age))
			log_adminwarn("Player [ckey] is new to the server ([player_age] days). Antigrief has been applied.")
			antigrief = TRUE

	if(config.min_byond_age)
		if(config.min_byond_age > player_byond_age)
			log_adminwarn("Failed Login: [key] - New account registered on [byond_join_date] (Age: [player_byond_age] days) - Minimum: [config.min_byond_age] days.")
			message_admins("<span class='adminnotice'>Failed Login: [key] -  New account registered on [byond_join_date] (Age: [player_byond_age] days) - Minimum: [config.min_byond_age] days.</span>")
			to_chat(src, "Apologies, this server is not accepting newly registered byond accounts right now. Please try again later.")
			qdel(src)
			return 0

	//Panic bunker code
	if (isnum(player_age) && player_age == 0) //first connection
		if (config.panic_bunker && !holder && !deadmin_holder)
			log_adminwarn("Failed Login: [key] - New account attempting to connect during panic bunker")
			message_admins("<span class='adminnotice'>Failed Login: [key] - New account attempting to connect during panic bunker</span>")
			to_chat(src, "Sorry but the server is currently not accepting connections from never before seen players.")
			prefs.first_seen = null
			qdel(src)
			return 0


	// IP Reputation Check
	if(config.ip_reputation)
		if(config.ipr_allow_existing && player_age >= config.ipr_minimum_age)
			log_admin("Skipping IP reputation check on [key] with [address] because of player age")
		else if(update_ip_reputation()) //It is set now
			if(ip_reputation >= config.ipr_bad_score) //It's bad


				message_admins("[key] at [address] has bad IP reputation: [ip_reputation]. Will be kicked if enabled in config.")
				log_admin("[key] at [address] has bad IP reputation: [ip_reputation]. Will be kicked if enabled in config.")

				//Take action if required
				if(config.ipr_block_bad_ips && config.ipr_allow_existing) //We allow players of an age, but you don't meet it
					to_chat(src,"Sorry, we only allow VPN/Proxy/Tor usage for players who have spent at least [config.ipr_minimum_age] days on the server. If you are unable to use the internet without your VPN/Proxy/Tor, please contact an admin out-of-game to let them know so we can accomidate this.")
					qdel(src)
					return 0
				else if(config.ipr_block_bad_ips) //We don't allow players of any particular age
					to_chat(src,"Sorry, we do not accept connections from users via VPN/Proxy/Tor connections.")
					qdel(src)
					return 0
		else
			log_admin("Couldn't perform IP check on [key] with [address]")


	//VOREStation Code

	var/alert = FALSE //VOREStation Edit start.
	if(isnum(player_age) && player_age == 0)
		message_admins("PARANOIA: [key_name(src)] has connected here for the first time.")
		alert = TRUE
	if(isnum(player_byond_age) && player_byond_age <= 2)
		message_admins("PARANOIA: [key_name(src)] has a very new BYOND account ([player_byond_age] days).")
		alert = TRUE
	if(alert)
		for(var/client/X in admins)
			if(X.is_preference_enabled(/datum/client_preference/holder/play_adminhelp_ping))
				X << 'sound/voice/Amogus.mp3'


	send_resources()
	SSnanoui.send_resources(src)

	if(!void)
		void = new()
		void.MakeGreed()
	screen += void

	if(prefs.lastchangelog != changelog_hash) //bolds the changelog button on the interface so we know there are updates.
		src << "<span class='info'>You have unread updates in the changelog.</span>"
		winset(src, "rpane.changelog", "background-color=#eaeaea;font-style=bold")
		if(config.aggressive_changelog)
			src.changes()

/client/proc/add_ip_cid_list(ip, cid)
	// This is for hard saving.
	if(ip && !(ip in prefs.ips_associated))
		prefs.ips_associated += ip

	if(cid && !(cid in prefs.cids_associated))
		prefs.cids_associated += cid



	//////////////
	//DISCONNECT//
	//////////////
/client/Del()
	if(holder)
		holder.owner = null
		admins -= src
	GLOB.directory -= ckey
	GLOB.clients -= src
	return ..()

/client/Destroy()
	..()
	return QDEL_HINT_HARDDEL_NOW

// here because it's similar to below

// Returns null if no DB connection can be established, or -1 if the requested key was not found in the database

/proc/get_player_age(key)
	establish_db_connection()
	if(!dbcon.IsConnected())
		if(config.hard_saving)
			var/player_mob = get_mob_by_key(key)
			return hard_save_player_age(player_mob)
		else
			return null

	var/sql_ckey = sql_sanitize_text(ckey(key))

	var/DBQuery/query = dbcon.NewQuery("SELECT datediff(Now(),firstseen) as age FROM erro_player WHERE ckey = '[sql_ckey]'")
	query.Execute()

	if(query.NextRow())
		return text2num(query.item[1])
	else
		return -1


/proc/hard_save_player_age(mob/M)
	if(!M || !M.client || !M.client.prefs)
		return 0

	var/age = 0

	age = text2num(Days_Difference(M.client.prefs.first_seen, M.client.prefs.last_seen))

	return age

/client/proc/get_byond_age()
	return text2num(Days_Difference(byond_join_date, full_real_time() ))


/client/proc/log_client_to_db()
	if ( IsGuestKey(src.key) )
		return

	if(config.hard_saving)
		player_age = hard_save_player_age(mob)

	establish_db_connection()
	if(!dbcon.IsConnected())
		return

	var/sql_ckey = sql_sanitize_text(src.ckey)

	var/DBQuery/query = dbcon.NewQuery("SELECT id, datediff(Now(),firstseen) as age FROM erro_player WHERE ckey = '[sql_ckey]'")
	query.Execute()
	var/sql_id = 0
	player_age = 0	// New players won't have an entry so knowing we have a connection we set this to zero to be updated if their is a record.
	while(query.NextRow())
		sql_id = query.item[1]
		player_age = text2num(query.item[2])
		break

	var/DBQuery/query_ip = dbcon.NewQuery("SELECT ckey FROM erro_player WHERE ip = '[address]'")
	query_ip.Execute()
	related_accounts_ip = ""
	while(query_ip.NextRow())
		related_accounts_ip += "[query_ip.item[1]], "
		break

	var/DBQuery/query_cid = dbcon.NewQuery("SELECT ckey FROM erro_player WHERE computerid = '[computer_id]'")
	query_cid.Execute()
	related_accounts_cid = ""
	while(query_cid.NextRow())
		related_accounts_cid += "[query_cid.item[1]], "
		break

	//Just the standard check to see if it's actually a number
	if(sql_id)
		if(istext(sql_id))
			sql_id = text2num(sql_id)
		if(!isnum(sql_id))
			return

	var/admin_rank = "Player"
	if(src.holder)
		admin_rank = src.holder.rank

	var/sql_ip = sql_sanitize_text(src.address)
	var/sql_computerid = sql_sanitize_text(src.computer_id)
	var/sql_admin_rank = sql_sanitize_text(admin_rank)

	if(sql_id)
		//Player already identified previously, we need to just update the 'lastseen', 'ip' and 'computer_id' variables
		var/DBQuery/query_update = dbcon.NewQuery("UPDATE erro_player SET lastseen = Now(), ip = '[sql_ip]', computerid = '[sql_computerid]', lastadminrank = '[sql_admin_rank]' WHERE id = [sql_id]")
		query_update.Execute()
	else
		//New player!! Need to insert all the stuff
		var/DBQuery/query_insert = dbcon.NewQuery("INSERT INTO erro_player (id, ckey, firstseen, lastseen, ip, computerid, lastadminrank) VALUES (null, '[sql_ckey]', Now(), Now(), '[sql_ip]', '[sql_computerid]', '[sql_admin_rank]')")
		query_insert.Execute()

	//Logging player access
	var/serverip = "[world.internet_address]:[world.port]"
	var/DBQuery/query_accesslog = dbcon.NewQuery("INSERT INTO `erro_connection_log`(`id`,`datetime`,`serverip`,`ckey`,`ip`,`computerid`) VALUES(null,Now(),'[serverip]','[sql_ckey]','[sql_ip]','[sql_computerid]');")
	query_accesslog.Execute()

#undef UPLOAD_LIMIT
#undef MIN_CLIENT_VERSION

//checks if a client is afk
//3000 frames = 5 minutes
/client/proc/is_afk(duration=3000)
	if(inactivity > duration)	return inactivity
	return 0

//gets byond age
/client/proc/findJoinDate()
	var/list/http = world.Export("http://byond.com/members/[ckey]?format=text")
	if(!http)
		log_world("Failed to connect to byond member page to age check [ckey]")
		return
	var/F = file2text(http["CONTENT"])
	if(F)
		var/regex/R = regex("joined = \"(\\d{4}-\\d{2}-\\d{2})\"")
		if(R.Find(F))
			var/new_date = R.group[1]

			//get year
			var/year = "[copytext(new_date, 1,5)]"
			var/month = "[copytext(new_date, 6,8)]"
			var/day = "[copytext(new_date, 9)]"

			return "[day]/[month]/[year]"
		else
			CRASH("Age check regex failed for [src.ckey]")

// Byond seemingly calls stat, each tick.
// Calling things each tick can get expensive real quick.
// So we slow this down a little.
// See: http://www.byond.com/docs/ref/info.html#/client/proc/Stat
/client/Stat()
	. = ..()
	if (holder)
		sleep(1)
	else
		sleep(5)
		stoplag()

/client/proc/last_activity_seconds()
	return inactivity / 10

//send resources to the client. It's here in its own proc so we can move it around easiliy if need be
/client/proc/send_resources()

	getFiles(
		'html/search.js',
		'html/panels.css',
		'html/images/loading.gif',
		'html/images/ntlogo.png',
		'html/images/sglogo.png',
		'html/images/talisman.png',
		'html/images/paper_bg.png',
		'icons/pda_icons/pda_atmos.png',
		'icons/pda_icons/pda_back.png',
		'icons/pda_icons/pda_bell.png',
		'icons/pda_icons/pda_blank.png',
		'icons/pda_icons/pda_boom.png',
		'icons/pda_icons/pda_bucket.png',
		'html/images/no_image32.png',
		'icons/pda_icons/pda_crate.png',
		'icons/pda_icons/pda_cuffs.png',
		'icons/pda_icons/pda_eject.png',
		'icons/pda_icons/pda_exit.png',
		'icons/pda_icons/pda_flashlight.png',
		'icons/pda_icons/pda_honk.png',
		'icons/pda_icons/pda_mail.png',
		'icons/pda_icons/pda_medical.png',
		'icons/pda_icons/pda_menu.png',
		'icons/pda_icons/pda_mule.png',
		'icons/pda_icons/pda_notes.png',
		'icons/pda_icons/pda_power.png',
		'icons/pda_icons/pda_rdoor.png',
		'icons/pda_icons/pda_reagent.png',
		'icons/pda_icons/pda_refresh.png',
		'icons/pda_icons/pda_scanner.png',
		'icons/pda_icons/pda_signaler.png',
		'icons/pda_icons/pda_status.png',
		'icons/spideros_icons/sos_1.png',
		'icons/spideros_icons/sos_2.png',
		'icons/spideros_icons/sos_3.png',
		'icons/spideros_icons/sos_4.png',
		'icons/spideros_icons/sos_5.png',
		'icons/spideros_icons/sos_6.png',
		'icons/spideros_icons/sos_7.png',
		'icons/spideros_icons/sos_8.png',
		'icons/spideros_icons/sos_9.png',
		'icons/spideros_icons/sos_10.png',
		'icons/spideros_icons/sos_11.png',
		'icons/spideros_icons/sos_12.png',
		'icons/spideros_icons/sos_13.png',
		'icons/spideros_icons/sos_14.png',
		'websites/website_images/ntoogle_logo.png',
		'websites/website_images/ntoogle_search.png',
		'websites/website_images/seized.png'
		)


/mob/proc/MayRespawn()
	return 0


/client/proc/MayRespawn()
	if(mob)
		return mob.MayRespawn()

	// Something went wrong, client is usually kicked or transfered to a new mob at this point
	return 0


/*
client/verb/character_setup()
	set name = "Character Setup"
	set category = "Preferences"
	if(prefs)
		prefs.ShowChoices(usr)
*/

/client/proc/can_harm_ssds()
	if(!config.ssd_protect)
		return 1
	if(bypass_ssd_guard)
		return 1
	if(mob && (mob.job in security_positions))
		return 1
	if(mob && (mob.job in medical_positions))
		return 1
	if(check_rights(R_ADMIN, 0, mob))
		return 1
	return 0


/client/proc/IsAntiGrief()
	if(!config.byond_antigrief_age)
		return FALSE

	return antigrief

/mob/proc/IsAntiGrief()
	if(!client)
		return FALSE
	if(jobban_isbanned(src, "Grief"))
		return TRUE

	return client.IsAntiGrief()

//This is for getipintel.net.
//You're welcome to replace this proc with your own that does your own cool stuff.
//Just set the client's ip_reputation var and make sure it makes sense with your config settings (higher numbers are worse results)
/client/proc/update_ip_reputation()
	var/request = "http://check.getipintel.net/check.php?ip=[address]&contact=[config.ipr_email]"
	var/http[] = world.Export(request)

	/* Debug
	world.log << "Requested this: [request]"
	for(var/entry in http)
		world.log << "[entry] : [http[entry]]"
	*/

	if(!http || !islist(http)) //If we couldn't check, the service might be down, fail-safe.
		log_admin("Couldn't connect to getipintel.net to check [address] for [key]")
		return FALSE

	//429 is rate limit exceeded
	if(text2num(http["STATUS"]) == 429)
		log_adminwarn("getipintel.net reports HTTP status 429. IP reputation checking is now disabled. If you see this, let a developer know.")
		config.ip_reputation = FALSE
		return FALSE

	var/content = file2text(http["CONTENT"]) //world.Export actually returns a file object in CONTENT
	var/score = text2num(content)
	if(isnull(score))
		return FALSE

	//Error handling
	if(score < 0)
		var/fatal = TRUE
		var/ipr_error = "getipintel.net IP reputation check error while checking [address] for [key]: "
		switch(score)
			if(-1)
				ipr_error += "No input provided"
			if(-2)
				fatal = FALSE
				ipr_error += "Invalid IP provided"
			if(-3)
				fatal = FALSE
				ipr_error += "Unroutable/private IP (spoofing?)"
			if(-4)
				fatal = FALSE
				ipr_error += "Unable to reach database"
			if(-5)
				ipr_error += "Our IP is banned or otherwise forbidden"
			if(-6)
				ipr_error += "Missing contact info"

		log_adminwarn(ipr_error)
		if(fatal)
			config.ip_reputation = FALSE
			log_adminwarn("With this error, IP reputation checking is disabled for this shift. Let a developer know.")
		return FALSE

	//Went fine
	else
		ip_reputation = score
		return TRUE
