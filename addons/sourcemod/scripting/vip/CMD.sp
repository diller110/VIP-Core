
void CMD_Setup()
{
	RegConsoleCmd("sm_refresh_vips",	ReloadVIPPlayers_CMD);
	RegConsoleCmd("sm_reload_vip_cfg",	ReloadVIPCfg_CMD);
	RegConsoleCmd("sm_addvip",			AddVIP_CMD);
	RegConsoleCmd("sm_delvip",			DelVIP_CMD);

	#if DEBUG_MODE 1
	RegConsoleCmd("sm_vip_dump_features",	DumpFeatures_CMD);
	#endif
}

public void OnConfigsExecuted()
{
	static bool bIsRegistered;
	if (bIsRegistered == false)
	{
		UTIL_LoadVipCmd(g_CVAR_hVIPMenu_CMD, VIPMenu_CMD);
		
		bIsRegistered = true;
	}
}

#define CHECK_ACCESS(%0) if (%0 && !(GetUserFlagBits(%0) & g_CVAR_iAdminFlag)) \
						{ \
							ReplyToCommand(%0, "[VIP] %t", "COMMAND_NO_ACCESS"); \
							return Plugin_Handled; \
						}

#if USE_ADMINMENU 1
public Action VIPAdmin_CMD(int iClient, int iArgs)
{
	if (iClient)
	{
		CHECK_ACCESS(iClient)
		
	//	g_hTopMenu.Display(iClient, TopMenuPosition_Start); //g_hTopMenu.Display(iClient, MENU_TIME_FOREVER);
		g_hVIPAdminMenu.Display(iClient, MENU_TIME_FOREVER);
	}
	
	return Plugin_Handled;
}
#endif

public Action ReloadVIPPlayers_CMD(int iClient, int iArgs)
{
	CHECK_ACCESS(iClient)
	
	UTIL_ReloadVIPPlayers(iClient, true);
	
	return Plugin_Handled;
}

public Action ReloadVIPCfg_CMD(int iClient, int iArgs)
{
	CHECK_ACCESS(iClient)
	
	ReadConfigs();
	UTIL_ReloadVIPPlayers(iClient, false);
	ReplyToCommand(iClient, "[VIP] %t", "VIP_CFG_REFRESHED");
	
	return Plugin_Handled;
}

public Action AddVIP_CMD(int iClient, int iArgs)
{
	CHECK_ACCESS(iClient)

	if (iArgs != 3)
	{
		ReplyToCommand(iClient, "[VIP] %t!\nSyntax: sm_addvip <#steam_id|#name|#userid> <group> <time>", "INCORRECT_USAGE");
		return Plugin_Handled;
	}
	
	char szBuffer[64], szTargetName[MAX_TARGET_LENGTH];
	GetCmdArg(1, SZF(szBuffer));

	int[] iTargetList = new int[MaxClients];
	bool bIsMulti;
	int iTargets, iAccountID = 0;

	if((iTargets = ProcessTargetString(
			szBuffer,
			iClient, 
			iTargetList, 
			MaxClients, 
			COMMAND_FILTER_CONNECTED|COMMAND_FILTER_NO_BOTS,
			SZF(szTargetName),
			bIsMulti)) < 1)
	{
		iAccountID = UTIL_GetAccountIDFromSteamID(szBuffer);
		if(!iAccountID)
		{
			ReplyToTargetError(iClient, iTargets);
			return Plugin_Handled;
		}
	}

	char szGroup[64];
	GetCmdArg(3, SZF(szGroup));
	int iTime = StringToInt(szGroup);
	if (iTime < 0)
	{
		ReplyToCommand(iClient, "[VIP] %t", "INCORRECT_TIME");
		return Plugin_Handled;
	}

	szGroup[0] = 0;
	GetCmdArg(2, SZF(szGroup));
	if (!szGroup[0] || !UTIL_CheckValidVIPGroup(szGroup))
	{
		ReplyToCommand(iClient, "%t", "VIP_GROUP_DOES_NOT_EXIST");
		return Plugin_Handled;
	}

	if(iTargets > 0)
	{
		for(int i = 0; i < iTargets; ++i)
		{
			if(IsClientInGame(iTargetList[i]))
			{
				if (g_iClientInfo[iTargetList[i]] & IS_VIP)
				{
					ReplyToCommand(iClient, "[VIP] %t", "ALREADY_HAS_VIP");
					continue;
				}
				
				UTIL_ADD_VIP_PLAYER(iClient, iTargetList[i], _, UTIL_TimeToSeconds(iTime), szGroup);
			}
		}
	
		return Plugin_Handled;
	}
	
	UTIL_ADD_VIP_PLAYER(iClient, _, iAccountID, UTIL_TimeToSeconds(iTime), szGroup);

	return Plugin_Handled;
}

public Action DelVIP_CMD(int iClient, int iArgs)
{
	CHECK_ACCESS(iClient)

	if (iArgs != 1)
	{
		ReplyToCommand(iClient, "%t!\nSyntax: sm_delvip <identity>", "INCORRECT_USAGE");
		return Plugin_Handled;
	}
	
	char sQuery[512], szAuth[MAX_NAME_LENGTH];
	GetCmdArg(1, szAuth, sizeof(szAuth));
	
	int iAccountID = UTIL_GetAccountIDFromSteamID(szAuth);
	if(!iAccountID)
	{
		ReplyToTargetError(iClient, COMMAND_TARGET_NONE);
		return Plugin_Handled;
	}

	if (GLOBAL_INFO & IS_MySQL)
	{
		FormatEx(sQuery, sizeof(sQuery), "SELECT `id` \
											FROM `vip_users` AS `u` \
											LEFT JOIN `vip_users_overrides` AS `o` \
											ON `o`.`user_id` = `u`.`id` \
											WHERE `o`.`server_id` = '%i' \
											AND `u`.`account_id` = %d LIMIT 1;", g_CVAR_iServerID, iAccountID);
	}
	else
	{
		FormatEx(sQuery, sizeof(sQuery), "SELECT `id` \
											FROM `vip_users` \
											WHERE `account_id` = %d LIMIT 1;", iAccountID);
	}
	
	DebugMessage(sQuery)
	if (iClient)
	{
		iClient = UID(iClient);
	}

	g_hDatabase.Query(SQL_Callback_OnSelectRemoveClient, sQuery, iClient);

	return Plugin_Handled;
}

public void SQL_Callback_OnSelectRemoveClient(Database hOwner, DBResultSet hQuery, const char[] sError, any iClient)
{
	if (hQuery == null || sError[0])
	{
		LogError("SQL_Callback_OnSelectRemoveClient: %s", sError);
	}
	
	if (iClient)
	{
		iClient = CID(iClient);
	}
	
	if ((hQuery).FetchRow())
	{
		DB_RemoveClientFromID(iClient, hQuery.FetchInt(0), true);
	}
	else
	{
		ReplyToCommand(iClient, "%t", "FIND_THE_ID_FAIL");
	}
}

#if DEBUG_MODE 1
public Action DumpFeatures_CMD(int iClient, int iArgs)
{
	CHECK_ACCESS(iClient)
	
	int iFeatures = g_hFeaturesArray.Length;
	if(iFeatures != 0)
	{
		char sBuffer[PLATFORM_MAX_PATH];
		BuildPath(Path_SM, sBuffer, sizeof(sBuffer), "data/vip/features_dump.txt");
		File hFile = OpenFile(sBuffer, "w");

		if(hFile != null)
		{
			char				sPluginName[64];
			char				sPluginPath[PLATFORM_MAX_PATH];
			char				sPluginVersion[32];
			char				sFeatureName[FEATURE_NAME_LENGTH];
			char				sFeatureType[32];
			char				sFeatureValType[32];
			ArrayList			hArray;
			Handle				hPlugin;

			for(int i = 0; i < iFeatures; ++i)
			{
				g_hFeaturesArray.GetString(i, sFeatureName, sizeof(sFeatureName));
				if(GLOBAL_TRIE.GetValue(sFeatureName, hArray))
				{
					hPlugin = view_as<Handle>(hArray.Get(FEATURES_PLUGIN));
					GetPluginInfo(hPlugin, PlInfo_Name, SZF(sPluginName));
					GetPluginInfo(hPlugin, PlInfo_Version, SZF(sPluginVersion));
					GetPluginFilename(hPlugin, SZF(sPluginPath));
					
					switch(view_as<VIP_FeatureType>(hArray.Get(FEATURES_ITEM_TYPE)))
					{
						case TOGGLABLE:		strcopy(SZF(sFeatureType), "TOGGLABLE");
						case SELECTABLE:	strcopy(SZF(sFeatureType), "SELECTABLE");
						case HIDE:			strcopy(SZF(sFeatureType), "HIDE");
					}
					
					switch(view_as<VIP_ValueType>(hArray.Get(FEATURES_VALUE_TYPE)))
					{
						case VIP_NULL:		strcopy(SZF(sFeatureValType), "VIP_NULL");
						case INT:			strcopy(SZF(sFeatureValType), "INT");
						case FLOAT:			strcopy(SZF(sFeatureValType), "FLOAT");
						case BOOL:			strcopy(SZF(sFeatureValType), "BOOL");
						case STRING:		strcopy(SZF(sFeatureValType), "STRING");
					}
					
					hFile.WriteLine("%d. %-32s %-16s %-16s %-64s %-32s %-256s", i, sFeatureName, sFeatureType, sFeatureValType, sPluginName, sPluginVersion, sPluginPath);
				}
			}
		}

		delete hFile;
	}
	
	return Plugin_Handled;
}
#endif

public Action VIPMenu_CMD(int iClient, int iArgs)
{
	if (iClient)
	{
		if (OnVipMenuFlood(iClient) == false)
		{
			if (g_iClientInfo[iClient] & IS_VIP)
			{
				g_hVIPMenu.Display(iClient, MENU_TIME_FOREVER);
			}
			else
			{
				/*
				PrintToChat(iClient, "%t%t", "VIP_CHAT_PREFIX", "COMMAND_NO_ACCESS");
				*/
				
				PlaySound(iClient, NO_ACCESS_SOUND);
				DisplayClientInfo(iClient, "no_access_info");
			}
		}
	}
	return Plugin_Handled;
}