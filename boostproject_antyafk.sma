#include <amxmodx>
#include <reapi>
#include <engine>
#include <CromChat>
#include <easy_http>

static const NAME[]		= "[CS 1.6] Anty AFK for BoostProject";
static const VERSION[]	= "1.0.1";
static const AUTHOR[]	= "AMXX4u";
static const URL_AUTHOR[] = "https://amxx4u.pl/";

#if !defined ForPlayers
	#define ForPlayers(%1) for(new %1 = 1; %1 <= MAX_PLAYERS; %1++)
#endif

#if !defined isPlayer
	#define isPlayer(%1) ((1 <= %1 && %1 <= MAX_PLAYERS))
#endif

// #define DEBUG_MODE 

#define TIMER_UPDATE_API 934821
#define TIMER_UPDATE_DATA 240.0 // Co ile sekund aktualizowac dane (API)

new Float:spawn_position[MAX_PLAYERS+1][3];
new bool:Checking[MAX_PLAYERS + 1];
new AfkCounter[MAX_PLAYERS + 1];

enum _:PLAYER_TIME {
	Time_Connection,
	Time_Kill,
	Time_Current
};

enum _:AFK_CVARS {
	APIKEY[MAX_NAME_LENGTH * 2],
	Float:TIMER_SPAWN,
	Float:TIMER_MENU,
	Action
};

new Time[MAX_PLAYERS+1][PLAYER_TIME];
new SpectTime[MAX_PLAYERS+1][PLAYER_TIME];
new ActiveBoostersSteamID[MAX_PLAYERS+1][MAX_AUTHID_LENGTH];
new config[AFK_CVARS];
new NumActiveBoosters = 0;

static const MENU_TITLE[] = "\d[ # BoostProject :: Anty AFK #]^n\y[AFK]\w"
static const MENU_PREFIX[] = "\d»\w"
static const FILE_LOG[] = "boostproject_api.log";
static const PREFIX[] = "[ BOOSTPROJECT ]";

public plugin_init() {
	register_plugin(NAME, VERSION, AUTHOR, URL_AUTHOR);

	register_clcmd("say /afk", "Menu_CheckPlayer");
	register_clcmd("jointeam", "Listener_JoinTeam");
	register_clcmd("chooseteam", "Listener_JoinTeam");

	RegisterHookChain(RG_CBasePlayer_Spawn, "player_spawn", true);
	RegisterHookChain(RG_CSGameRules_DeathNotice, "player_death", true);

	bind_pcvar_string(create_cvar("boost_apikey", "",
		.description = "Klucz API ze strony"), config[APIKEY], charsmax(config[APIKEY]));
	bind_pcvar_float(create_cvar("boost_spawntimer", "20.0",
		.description = "Po ilu sekundach od odrodzenia gracza sprawdzić jego status gry"), config[TIMER_SPAWN]);
	bind_pcvar_float(create_cvar("boost_menutimer", "15.0",
		.description = "Ile sekund będzie miał gracz na wybranie odpowiedniej opcji w menu"), config[TIMER_MENU]);
	bind_pcvar_num(create_cvar("boost_action", "0",
		.description = "Co zrobić gdy booster jest nieaktywny? [ 0 - kick | inne - długość bana w minutach ]"), config[Action]);
}

public plugin_cfg() {
	server_print("[BoostProject] Klucz API: %s", config[APIKEY]);

	if(strlen(config[APIKEY]) < 3)
		set_fail_state("[BoostProject] Nie podano żadnego klucza api.");
	else {
		AFK_UpdateArray();
		set_task(TIMER_UPDATE_DATA, "Timer_UpdateApi", .flags = "b");
	}
}

public Timer_UpdateApi() {
	new attempts;
	new bool:bAttempts;

	if(attempts >= 5) {
		log_to_file(FILE_LOG, "Nie mozna bylo nawiazac polaczenia z API");
		set_fail_state("%s Nie mozna bylo nawiazac polaczenia z API.", PREFIX);
	}

	if(bAttempts)
		attempts++;

	AFK_UpdateArray();
}

public client_putinserver(id) {
	if(is_user_hltv(id) || is_user_bot(id))
		return;

	ResetPlayer(id);
	Time[id][Time_Connection] = get_systime();

	#if defined DEBUG_MODE
		log_amx("%s [client_putinserver] %d", PREFIX, Time[id][Time_Connection]);
	#endif
}

public client_disconnected(id) {
	if(is_user_hltv(id) || is_user_bot(id))
		return;

	new steamID[MAX_AUTHID_LENGTH];
	get_user_authid(id, steamID, charsmax(steamID));
}

public ResetPlayer(id) 
{
	spawn_position[id][0] = 0.0;
	spawn_position[id][1] = 0.0;
	spawn_position[id][2] = 0.0;

	Checking[id] = false;

	Time[id][Time_Connection] = 0;
	Time[id][Time_Kill] = 0;

	AfkCounter[id] = 0;
}

public player_spawn(id) {
	if(!is_user_alive(id) || is_user_bot(id))
		return HC_CONTINUE;

	new freezetime = get_cvar_num("mp_freezetime");
	entity_get_vector(id, EV_VEC_origin, spawn_position[id]);

	set_task(config[TIMER_SPAWN] + freezetime, "Timer_CheckPlayer", id);
	return HC_CONTINUE;
}

public Timer_CheckPlayer(id) {
	if(!is_user_alive(id) || is_user_bot(id) || !IsPlayerActiveBooster(id))
		return PLUGIN_HANDLED;

	new Float:CurrentPosition[3];
	entity_get_vector(id, EV_VEC_origin, CurrentPosition);

	if(get_distance_f(CurrentPosition, spawn_position[id]) > 200.0)
		return PLUGIN_HANDLED;

	AFK_CheckPlayer(id);
	return PLUGIN_HANDLED;
}

public AFK_CheckPlayer(id) {
	if(!is_user_connected(id))
		return;

	AfkCounter[id] ++;
	Checking[id] = true;

	CC_SendMessage(id, "&x07[		&x01» &x07ANTY AFK &x01«		&x07]");
	CC_SendMessage(id, "&x04» &x01Sprawdzamy czy jesteś AFK.");
	CC_SendMessage(id, "&x04» &x01Jeśli nie wyświetlilo Ci sie menu wpisz &x04/afk&x01.");
	CC_SendMessage(id, "&x07[		&x01» &x07ANTY AFK &x01«		&x07]");

	set_task(config[TIMER_MENU], "Timer_TimeToCheck", id);
	Menu_CheckPlayer(id);
}

public Menu_CheckPlayer(id) {
	new menu = menu_create(fmt("%s Wybierz opcje ktora zawiera nazwe\y BoostProject", MENU_TITLE), "Menu_CheckPlayerCallback");
	new random = random_num(0, 4);

	for(new i = 0; i < 5; i++) {
		if(i == random)
			menu_additem(menu, fmt("%s BoostProject", MENU_PREFIX), "correct");
		else
			menu_additem(menu, fmt("%s Jestem afk B-)", MENU_PREFIX), "kick");
	}

	menu_setprop(menu, MPROP_EXITNAME, fmt("%s Wyjdz", MENU_PREFIX));
	menu_display(id, menu);
}

public Menu_CheckPlayerCallback(id, menu, item) {
	if(item == MENU_EXIT) {
		menu_destroy(menu);
		return PLUGIN_HANDLED;
	}

	if(!is_user_connected(id) || !Checking[id])
		return PLUGIN_HANDLED;

	new data[MAX_PLAYERS];
	new access, callback;

	menu_item_getinfo(menu, item, access, data, charsmax(data), .callback = callback);

	if(equal(data, "correct")) {
		Checking[id] = false;

		CC_SendMessage(id, "&x04BoostProject » &x01Udalo Ci sie przejsc test, miej sie jednak na bacznosci.");
		set_task(config[TIMER_SPAWN], "Timer_CheckPlayer", id);
	}
	else
		AFK_ActionWithClient(id);

	return PLUGIN_HANDLED;
}

public AFK_ActionWithClient(id) {
	if(config[Action] == 0)
		rh_drop_client(id, fmt("%s Zostales wyrzucony z powodu nieaktywnosci.", PREFIX));
	else
		server_cmd(fmt("amx_ban %n %d %s Zostales zbanowany na %d minut. Powod: AFK.", id, config[Action], config[Action], PREFIX));
}

public player_death(victim, attacker) {
	if(!isPlayer(attacker) || !isPlayer(victim) || !is_entity(victim) || victim == attacker || attacker == 0 || victim == 0)
		return HC_CONTINUE;

	if(get_member(attacker, m_iTeam) == get_member(victim, m_iTeam))
		return HC_CONTINUE;

	Time[attacker][Time_Kill] = get_systime();

	#if defined DEBUG_MODE
		log_amx("%s [player_death] %d", PREFIX, Time[attacker][Time_Kill]);
	#endif

	return HC_CONTINUE;
}

public Listener_JoinTeam(id) {
	if (!is_user_connected(id))
		return PLUGIN_CONTINUE;

	new const currentTime = get_systime();
	new currentTeam = get_user_team(id);
	new previousTeam = SpectTime[id][Time_Connection] > 0 ? 3 : -1;

	if(currentTeam == 3 && previousTeam != 3) {
		SpectTime[id][Time_Connection] = currentTime;

		#if defined DEBUG_MODE
			log_amx("%s [Listener_JoinTeam] Gracz %n dołączył do obserwatorów.", PREFIX, id);
		#endif
	}
	else if(previousTeam == 3 && currentTeam != 3) {
		new timeSpentAsSpectator = currentTime - SpectTime[id][Time_Connection];
		SpectTime[id][Time_Current] += timeSpentAsSpectator;

		#if defined DEBUG_MODE
			log_amx("%s [Listener_JoinTeam] Gracz %n spędził %d sekund jako obserwator i opuścił tę drużynę.", PREFIX, id, timeSpentAsSpectator);
		#endif

		SpectTime[id][Time_Connection] = 0;
	}

	return PLUGIN_CONTINUE;
}

public Timer_TimeToCheck(id) {
	if(!is_user_connected(id) || !Checking[id])
		return PLUGIN_HANDLED;

	AFK_ActionWithClient(id);
	return PLUGIN_HANDLED;
}

public AFK_UpdateArray() {
	new EzJSON:jsonRoot = ezjson_init_object();
	ezjson_object_set_string(jsonRoot, "version", VERSION);

	new EzJSON:jsonPlayers = ezjson_init_array();
	new team[12];

	new EzHttpOptions:options_id = ezhttp_create_options()

	ezhttp_option_set_header(options_id, "Content-Type", "application/json")

	ForPlayers(i) {
		if(!is_user_connected(i))
			continue;

		switch(get_member(i, m_iTeam)) {
			case TEAM_CT: formatex(team, charsmax(team), "CT");
			case TEAM_TERRORIST: formatex(team, charsmax(team), "TT");
			case TEAM_SPECTATOR: formatex(team, charsmax(team), "SPECT");
		}

		new steamID[MAX_AUTHID_LENGTH], playerName[MAX_NAME_LENGTH];
		get_user_authid(i, steamID, charsmax(steamID));
		get_user_name(i, playerName, charsmax(playerName));

		new connection_time = Time[i][Time_Connection];
		new kill_time = Time[i][Time_Kill];

		new EzJSON:jsonPlayer = ezjson_init_object();
		ezjson_object_set_string(jsonPlayer, "steamid64", steamID);
		ezjson_object_set_string(jsonPlayer, "name", playerName);
		ezjson_object_set_number(jsonPlayer, "kills", get_entvar(i, var_frags));
		ezjson_object_set_number(jsonPlayer, "deaths", get_member(i, m_iDeaths));
		ezjson_object_set_number(jsonPlayer, "seconds", get_systime() - connection_time);
		ezjson_object_set_number(jsonPlayer, "killSeconds", get_systime() - kill_time);
		ezjson_object_set_number(jsonPlayer, "connectionTime", Time[i][Time_Connection]);
		ezjson_object_set_number(jsonPlayer, "killTime", Time[i][Time_Kill]);
		ezjson_object_set_number(jsonPlayer, "spectSeconds", Time[i][Time_Current]);
		ezjson_object_set_string(jsonPlayer, "team", team);
		ezjson_object_set_number(jsonPlayer, "afkCounter", AfkCounter[i]);

		ezjson_array_append_value(jsonPlayers, jsonPlayer);
		ezjson_free(jsonPlayer);
	}

	ezjson_object_set_value(jsonRoot, "players", jsonPlayers);
	ezjson_object_set_string(jsonRoot, "key", config[APIKEY]);
	ezjson_free(jsonPlayers);

	new data[3048];
	ezjson_serial_to_string(jsonRoot, data, charsmax(data));
	ezhttp_option_set_body(options_id, data)

	#if defined DEBUG_MODE
		log_amx("%s %s", PREFIX, data);
	#endif

	ezjson_free(jsonRoot);
	ezhttp_post("http://api.boostproject.pro/plugin/send-data", "OnPlayersReceived", options_id);
}

public OnPlayersReceived(EzHttpRequest: httpRequest) 
{
	clearActiveBoosters();

	if(ezhttp_get_error_code(httpRequest) != EZH_OK) {
		set_task(5.0, "Timer_UpdateApi");

		new error[64];
		ezhttp_get_error_message(httpRequest, error, charsmax(error));

		log_to_file(FILE_LOG, "%s Error connecting to API: %s", PREFIX, error);
		server_print("%s Error connecting to API: %s", PREFIX, error);
		return;
	}

	new responseData[2048];

	while((ezhttp_get_data(httpRequest, responseData, sizeof(responseData))) > 0) {
		new EzJSON:responseJSON = ezjson_parse(responseData);

		if (responseJSON == EzInvalid_JSON) {
			ezjson_free(responseJSON);
			continue;
		}

		new bool:success = ezjson_object_get_bool(responseJSON, "success");
		if (!success) 
		{
			log_to_file(FILE_LOG, "%s API returned an error.", PREFIX);
			ezjson_free(responseJSON);
			return;
		}

		for(new i = 0; i < MAX_PLAYERS; ++i) {
			formatex(ActiveBoostersSteamID[i], MAX_AUTHID_LENGTH, "");
		}

		new EzJSON:dataArray = ezjson_object_get_value(responseJSON, "data");

		if(ezjson_is_array(dataArray)) {
			new size = ezjson_array_get_count(dataArray);
			for(new i = 0; i < size; ++i) {
				new EzJSON:jsonObject = ezjson_array_get_value(dataArray, i);
				if(ezjson_is_object(jsonObject)) {
					new steamid[32];
					new msg[128];
					ezjson_object_get_string(jsonObject, "steamid64", steamid, sizeof(steamid));
					ezjson_object_get_string(jsonObject, "msg", msg, sizeof(msg));

					updateActiveBoosterList(steamid);
					#if defined DEBUG_MODE
					    log_amx("[BoostProject] Dodano boostera: %s", steamid);
					#endif
				}
				ezjson_free(jsonObject);
			}
		}
		ezjson_free(dataArray);
		ezjson_free(responseJSON);
	}
}

public clearActiveBoosters() 
{
	NumActiveBoosters = 0;

	ForPlayers(i)
		format(ActiveBoostersSteamID[i], sizeof(ActiveBoostersSteamID[]), "");
    
	#if defined DEBUG_MODE
	    log_amx("[BoostProject] Wyczyszczono liste aktywnych boosterow.");
	#endif
}

public updateActiveBoosterList(const steamid[]) 
{
    if (NumActiveBoosters < MAX_PLAYERS) 
	{
        copy(ActiveBoostersSteamID[NumActiveBoosters], charsmax(ActiveBoostersSteamID[]), steamid);
        NumActiveBoosters++;

		#if defined DEBUG_MODE
            log_amx("[BoostProject] Aktualizacja listy boosterow: %s", steamid);
		#endif
    } 
	else 
	{
		#if defined DEBUG_MODE
            log_amx("[BoostProject] Lista aktywnych boosterow jest pelna. Nie mozna dodac: %s", steamid);
		#endif
    }
}

public bool:IsPlayerActiveBooster(const id) 
{
	new steamID[MAX_AUTHID_LENGTH];
	get_user_authid(id, steamID, charsmax(steamID));

	for (new i = 0; i < NumActiveBoosters; ++i) {
		if (equal(steamID, ActiveBoostersSteamID[i])) {
			return true;
		}
	}
	return false;
}