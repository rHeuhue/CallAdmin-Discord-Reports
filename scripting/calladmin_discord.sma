#include <amxmodx>
#include <regex>

#define VERSION "1.0"

// You must create WebHook in channel you want the report system to send the information..
new g_szWebHook[1024] = "https://discord.com/api/webhooks/";


#include <curl>

#pragma dynamic 32768

// All the data for those defines must be provided!

#define SERVER_NAME "Your Server Name Here"
#define SERVER_URL "https://www.gametracker.rs/server_info/IP:PORT/" //Example:  https://www.gametracker.rs/server_info/192.168.0.1:27015/
#define SERVER_IP "Your Server IP Here" // Example: 192.168.0.1:27015
#define THUMBNAIL "https://avatars.githubusercontent.com/u/83426246?v=4" // Your Thumbnail avatar here [This one is mine from the github]
#define BANNER	"https://banners.gametracker.rs/Your_IP_Here/big/red/banner.jpg" // GameTracker.RS banner immage | Example: https://banners.gametracker.rs/192.168.0.1:27015/big/red/banner.jpg
#define AVATAR  "https://avatars.githubusercontent.com/u/83426246?v=4"	// Avatar for the discord profile [This one is mine from the github]
#define USERNAME "CallAdmin Report System"	// Username to set the discord webhook for easy reading on the reports
#define FOOTER_ICON "https://avatars.githubusercontent.com/u/83426246?v=4" // Footer icon [also my avatar from github | little cirle image at the bottom of the report]
#define FOOTER_TEXT "CallAdmin Report System" // Footer text at the bottom next to the icon

// To retrieve mention role you have to copy role id from discord and pasting it here. The role syntax is <@&RoleID> Example: <@&111111111111111111>
// To retrieve mention role from discord: 1. @Rele 2. Add \ in front of @Role >> \@Role 3. Press Enter it will print text: <@&111111111111111111> replace your numbers with the ones here																				
#define MENTION_ROLE "<@&111111111111111111>"

#define CURL_BUFFER_SIZE 4096

new g_iReportedPlayerId[MAX_PLAYERS + 1];

new Trie:g_tAntiFlood, Float:g_iAntiFlood[MAX_PLAYERS + 1];
new g_pC_AntiFloodEnabled, Float:g_pC_AntiFloodTime;

new g_pC_Prefix[MAX_NAME_LENGTH];


public plugin_init()
{
	register_plugin("CallAdmin System Discord Reports [CURL]", VERSION, "Huehue @ AMXX-BG.INFO");
	
	register_clcmd("say /calladmin", "CallAdmin_PlayersMenu");
	register_clcmd("say_team /calladmin", "CallAdmin_PlayersMenu");

	register_clcmd("CAS_TYPE_REPORT_REASON", "Command_ReportCustomReason");

	bind_pcvar_string(create_cvar("cas_prefix", "[Call Admin System]", FCVAR_NONE, "Prefix for the menu and the chat messages"), g_pC_Prefix, charsmax(g_pC_Prefix));
	
	g_tAntiFlood = TrieCreate();
	bind_pcvar_num(create_cvar("cas_antiflood_status", "1", FCVAR_NONE, "Anti flooding reports"), g_pC_AntiFloodEnabled);
	bind_pcvar_float(create_cvar("cas_antiflood_seconds", "30.0", FCVAR_NONE, "How many seconds to wait before player next report"), g_pC_AntiFloodTime); // 300.0
}

public plugin_end()
{
	TrieDestroy(g_tAntiFlood);
}
    
public client_authorized(id, const authid[])
{
	if (g_pC_AntiFloodEnabled)
	{	
		if (!TrieGetCell(g_tAntiFlood, authid, g_iAntiFlood[id]))
		{
			g_iAntiFlood[id] = 0.0;
		}
	}
	
	g_iReportedPlayerId[id] = 0;
}

public client_disconnected(id)
{
	if (g_pC_AntiFloodEnabled)
	{
		if (get_gametime() - g_iAntiFlood[id] < g_pC_AntiFloodTime)
		{
			new szAuthID[MAX_AUTHID_LENGTH];
			get_user_authid(id, szAuthID, charsmax(szAuthID));
			TrieSetCell(g_tAntiFlood, szAuthID, g_iAntiFlood[id]);
		}
	}
}

public CallAdmin_PlayersMenu(id)
{
	if (g_pC_AntiFloodEnabled && get_gametime() - g_iAntiFlood[id] < g_pC_AntiFloodTime)
	{
		client_print_color(id, print_team_default, "^4%s ^1You can file a new complaint in^4 %.f seconds^1!", g_pC_Prefix, g_pC_AntiFloodTime - (get_gametime() - g_iAntiFlood[id]));
		return PLUGIN_HANDLED;
	}

	new iMenu = menu_create(fmt("\y%s \wChoose a player to \rreport\w:", g_pC_Prefix), "reportmenu_handler");
	new iMenu_Callback = menu_makecallback("reportmenu_callback");

	new iPlayers[MAX_PLAYERS], iNum, iPlayer;
	get_players(iPlayers, iNum);
	
	for (--iNum; iNum >= 0; iNum--)
	{
		iPlayer = iPlayers[iNum];
			
		if (id != iPlayer)
		{
			menu_additem(iMenu, fmt("%n", iPlayer), fmt("%i", get_user_userid(iPlayer)), .callback = iMenu_Callback);
		}
	}
	menu_display(id, iMenu, 0);
	return PLUGIN_HANDLED;
}

public reportmenu_callback(id, iMenu, Item)
{
	new szData[MAX_PLAYERS], szName[MAX_NAME_LENGTH * 2];
	new _access, item_callback;
	menu_item_getinfo(iMenu, Item, _access, szData, charsmax(szData), szName, charsmax(szName), item_callback);

	new iPlayer = find_player_ex(FindPlayer_MatchUserId, str_to_num(szData));

	if (get_user_flags(iPlayer) & ADMIN_IMMUNITY)
	{
		menu_item_setname(iMenu, Item, fmt("%s \d[\rImmunity\d]", szName));
		return ITEM_DISABLED;
	}
	return ITEM_ENABLED;
}

public reportmenu_handler(id, iMenu, Item)
{
	if (Item == MENU_EXIT)
	{
		menu_destroy(iMenu);
		return PLUGIN_HANDLED;
	}
	
	new szData[MAX_PLAYERS], szName[MAX_NAME_LENGTH * 2];
	new _access, item_callback;
	menu_item_getinfo(iMenu, Item, _access, szData, charsmax(szData), szName, charsmax(szName), item_callback);
	
	new iPlayer = find_player_ex(FindPlayer_MatchUserId, str_to_num(szData));

	if (!iPlayer)
	{
		client_print_color(id, print_team_default, "^4%s ^1The ^4player ^1is ^4not found ^1[Either disconnected or Invalid!]", g_pC_Prefix);
		return PLUGIN_HANDLED;
	}
	
	g_iReportedPlayerId[id] = iPlayer;

	client_cmd(id, "messagemode CAS_TYPE_REPORT_REASON");
	client_print_color(id, print_team_default, "^4%s ^1Type in the ^3reason^1, or ^4!cancel ^1to ^3cancel^1.", g_pC_Prefix);

	menu_destroy(iMenu);
	return PLUGIN_HANDLED;
}

public Command_ReportCustomReason(id)
{
	if (!is_user_connected(g_iReportedPlayerId[id]))
		return PLUGIN_HANDLED;

	new szReason[MAX_FMT_LENGTH];
	read_argv(1, szReason, charsmax(szReason));

	if (equali(szReason, "!cancel"))
	{
		g_iReportedPlayerId[id] = 0;
		return PLUGIN_HANDLED;
	}

	if (is_invalid(szReason))
	{
		client_print_color(id, print_team_red, "^4%s ^3Advertisements are forbidden!", g_pC_Prefix);
		return PLUGIN_HANDLED;
	}

	g_iAntiFlood[id] = get_gametime();

	ShowToAdmins(id, g_iReportedPlayerId[id], szReason);
	
	send_discord_message(id, g_iReportedPlayerId[id], szReason);
	
	g_iReportedPlayerId[id] = 0;
	return PLUGIN_HANDLED;
}

public ShowToAdmins(id, iReportedPlayerId, szReason[MAX_FMT_LENGTH])
{
	for (new iAdminId; iAdminId < MAX_PLAYERS; iAdminId++)
	{
		if (is_user_connected(iAdminId) && get_user_flags(iAdminId) & ADMIN_RCON)
		{
			replace_all(szReason, charsmax(szReason), "\d", "");
			replace_all(szReason, charsmax(szReason), "\r", "");
			replace_all(szReason, charsmax(szReason), "\y", "");
			replace_all(szReason, charsmax(szReason), "\w", "");
			client_print_color(iAdminId, print_team_default, "%s ^1Player ^3%n ^1has been reported by ^4%n ^1for reason ^3%s^1!", g_pC_Prefix, iReportedPlayerId, id, szReason);
			return PLUGIN_HANDLED;
		}
	}
	return PLUGIN_CONTINUE;
}

bool:is_invalid(const text[])
{
	new error[50], num;
	new Regex:regex = regex_match(text, "\b(?:\d{1,3}(\,|\<|\>|\~|\«|\»|\=|\.|\s|\*|\')){3}\d{1,3}\b", num, error, charsmax(error), "i");
	if(regex >= REGEX_OK)
	{
		regex_free(regex);
		return true;
	}
	regex = regex_match(text, "([1-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])(\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])){2}", num, error, charsmax(error));
	if(regex >= REGEX_OK)
	{
		regex_free(regex);
		return true;
	}
	
	regex = regex_match(text, "([1-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])(\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])){3}", num, error, charsmax(error));
	if(regex >= REGEX_OK)
	{
		regex_free(regex);
		return true;
	}
	
	regex = regex_match(text, "[a-zA-Z0-9\-\.]+\.(com|org|net|bg|info|COM|ORG|NET|BG|INFO)", num, error, charsmax(error));
	if(regex >= REGEX_OK)
	{
		regex_free(regex);
		return true;
	}
	
	regex = regex_match(text, "(?:\w+\.[a-z]{2,4}\b|(?:\s*\d+\s*\.){3})", num, error, charsmax(error));
	if(regex >= REGEX_OK)
	{
		regex_free(regex);
		return true;
	}

	return false;
}

//---------------------------------------
enum dataStruct { curl_slist: linkedList };
enum dataPlayerStruct { PLAYER_CALLED_AUTHID[MAX_AUTHID_LENGTH], PLAYER_REPORTED_AUTHID[MAX_AUTHID_LENGTH], PLAYER_REPORTED_IP[MAX_IP_LENGTH] }

public send_discord_message(id, iReportedPlayerId, const szReason[])
{
	new CURL: pCurl, curl_slist: pHeaders;
	new sData[dataStruct];
	pHeaders = curl_slist_append(pHeaders, "Content-Type: application/json");
	pHeaders = curl_slist_append(pHeaders, "User-Agent: pay-attention");
	pHeaders = curl_slist_append(pHeaders, "Connection: Keep-Alive");
	
	sData[linkedList] = pHeaders;

	new sDataPlayer[dataPlayerStruct];

	get_user_authid(id, sDataPlayer[PLAYER_CALLED_AUTHID], charsmax(sDataPlayer[PLAYER_CALLED_AUTHID]));
	get_user_authid(iReportedPlayerId, sDataPlayer[PLAYER_REPORTED_AUTHID], charsmax(sDataPlayer[PLAYER_REPORTED_AUTHID]));
	get_user_ip(iReportedPlayerId, sDataPlayer[PLAYER_REPORTED_IP], charsmax(sDataPlayer[PLAYER_REPORTED_IP]), 1);

	
	if ((pCurl = curl_easy_init()))
	{
		new text[CURL_BUFFER_SIZE];

		formatex(text, charsmax(text), 
					"{ ^"username^": ^"{username}^", \
						^"avatar_url^": ^"{avatar}^", \
						^"content^": ^"{mention_role} New report received^", \
						^"embeds^": \
							[ {  ^"author^": { ^"name^": ^"{server_name}^",  ^"url^": ^"{server_url}^" }, \
					            ^"color^": %d, ^"title^": ^"{server_ip}^", \
					            ^"footer^": {  ^"text^": ^"{footer_text}^",  ^"icon_url^": ^"{footer_icon}^" }, \
					            ^"thumbnail^": { ^"url^": ^"{thumbnail}^" }, \
					            ^"image^": { ^"url^": ^"{banner}^" }, \
					            ^"fields^": [ \
					            	{ ^"name^": ^"​\u200b^", ^"value^": ^"​\u200b^" }, \
					            	{ ^"name^": ^"Reporter^", ^"value^": ^"Name: {id_name} \nSteamID: {id_steamid}\n[Check Reporter Steam](https://www.steamidfinder.com/lookup/{id_steamid}/)^", ^"inline^": true }, \
					                { ^"name^": ^"​\u200b^", ^"value^": ^"​\u200b^" }, \
					                { ^"name^": ^"Reported^", ^"value^": ^"Name: {rp_name} \nSteamID: {rp_steamid} \nIP: {rp_ip}\n[Check Reported Steam](https://www.steamidfinder.com/lookup/{rp_steamid}/)^", ^"inline^": true }, \
					                { ^"name^": ^"​\u200b^", ^"value^": ^"​\u200b^" },\
					                { ^"name^": ^"Reason^", ^"value^": ^"{reason}^", ^"inline^": true }, \
					                { ^"name^": ^"​\u200b^", ^"value^": ^"​\u200b^" } \
					            	] \
					        	} \
					    	] \
					}", random(19141997));

		replace_string(text, charsmax(text), "{mention_role}", MENTION_ROLE);
		replace_string(text, charsmax(text), "{server_name}", SERVER_NAME);
		replace_string(text, charsmax(text), "{server_url}", SERVER_URL);
		replace_string(text, charsmax(text), "{server_ip}", SERVER_IP);
		replace_string(text, charsmax(text), "{thumbnail}", THUMBNAIL);
		replace_string(text, charsmax(text), "{banner}", BANNER);
		replace_string(text, charsmax(text), "{avatar}", AVATAR);
		replace_string(text, charsmax(text), "{username}", USERNAME);
		replace_string(text, charsmax(text), "{footer_icon}", FOOTER_ICON);
		replace_string(text, charsmax(text), "{footer_text}", FOOTER_TEXT);

		replace_string(text, charsmax(text), "{id_name}", fmt("%n", id));
		replace_string(text, charsmax(text), "{id_steamid}", sDataPlayer[PLAYER_CALLED_AUTHID]);
		replace_string(text, charsmax(text), "{rp_name}", fmt("%n", iReportedPlayerId));
		replace_string(text, charsmax(text), "{rp_steamid}", sDataPlayer[PLAYER_REPORTED_AUTHID]);
		replace_string(text, charsmax(text), "{rp_ip}", sDataPlayer[PLAYER_REPORTED_IP]);
		replace_string(text, charsmax(text), "{reason}", szReason);
	
		curl_easy_setopt(pCurl, CURLOPT_URL, g_szWebHook);
		curl_easy_setopt(pCurl, CURLOPT_COPYPOSTFIELDS, text);
		curl_easy_setopt(pCurl, CURLOPT_CUSTOMREQUEST, "POST");
		curl_easy_setopt(pCurl, CURLOPT_HTTPHEADER, pHeaders);
		curl_easy_setopt(pCurl, CURLOPT_SSL_VERIFYPEER, 0); 
		curl_easy_setopt(pCurl, CURLOPT_SSL_VERIFYHOST, 0); 
		curl_easy_setopt(pCurl, CURLOPT_SSLVERSION, CURL_SSLVERSION_TLSv1); 
		curl_easy_setopt(pCurl, CURLOPT_FAILONERROR, 0); 
		curl_easy_setopt(pCurl, CURLOPT_FOLLOWLOCATION, 0); 
		curl_easy_setopt(pCurl, CURLOPT_FORBID_REUSE, 0); 
		curl_easy_setopt(pCurl, CURLOPT_FRESH_CONNECT, 0); 
		curl_easy_setopt(pCurl, CURLOPT_CONNECTTIMEOUT, 10); 
		curl_easy_setopt(pCurl, CURLOPT_TIMEOUT, 10);
		curl_easy_setopt(pCurl, CURLOPT_POST, 1);
		curl_easy_setopt(pCurl, CURLOPT_WRITEFUNCTION, "@Response_Write");
		curl_easy_perform(pCurl, "@Request_Complete", sData, dataStruct);
	}
}

@Response_Write(const data[], const size, const nmemb)
{
	server_print("Response body: ^n%s", data);
	return size * nmemb;
}

@Request_Complete(CURL: curl, CURLcode: code, const data[dataStruct])
{
	curl_easy_cleanup(curl);
	curl_slist_free_all(data[linkedList]);
}
