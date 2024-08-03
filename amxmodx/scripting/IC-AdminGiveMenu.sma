#include <amxmodx>
#include <reapi>
#include <json>
#include <regex>
#include <VipM/ItemsController>

new const GIVE_COMMAND[] = "ic_admin_give_menu_give";

enum _:S_GiveMenu {
    GiveMenu_AccessFlags,
    GiveMenu_MenuTitle[128],
    Array:GiveMenu_MenuItems,
}

enum _:S_GiveMenuItem {
    GiveMenu_Title[128],
    Array:GiveMenuItem_Items,
}

new g_cfgFolder[] = "IC-AdminGiveMenu";

new Trie:g_menuCmds = Invalid_Trie;
new Array:g_menus = Invalid_Array;

public plugin_precache() {
    register_plugin("[IC] Admin Give Menu", "1.0.0", "ArKaNeMaN");
    register_dictionary("IC-AdminGiveMenu.ini");
    VipM_IC_Init();

    LoadMenusFromFolder(CfgUtils_MakePath("Menus"));

    register_clcmd(GIVE_COMMAND, "@CascadeClCmd_Give");
}

@ClCmd_OpenMenu(const playerIndex) {
    // То ли я тупой, то ли лыжи не едут... read_args почему-то не работает нормально)
    new cmd[128], cmdLen = 0;
    for (new i = 0; i < read_argc(); ++i) {
        if (cmdLen) {
            cmd[cmdLen++] = ' ';
        }
        cmdLen += read_argv(i, cmd[cmdLen], charsmax(cmd) - cmdLen);
    }

    if (!TrieKeyExists(g_menuCmds, cmd)) {
        return PLUGIN_CONTINUE;
    }

    new menuIndex;
    TrieGetCell(g_menuCmds, cmd, menuIndex);

    client_cmd(playerIndex, fmt("%s %d", GIVE_COMMAND, menuIndex));
    return PLUGIN_HANDLED;
}

@CascadeClCmd_Give(const playerIndex) {
    enum {Arg_MenuIndex = 1, Arg_PlayerIndex, Arg_MenuItemIndex}

    if (read_argc() <= Arg_MenuIndex) {
        return PLUGIN_HANDLED;
    }

    new menuIndex = read_argv_int(Arg_MenuIndex);

    new menu[S_GiveMenu];
    ArrayGetArray(g_menus, menuIndex, menu);

    if (menu[GiveMenu_AccessFlags] > 0 && !(get_user_flags(playerIndex) & menu[GiveMenu_AccessFlags])) {
        client_print(playerIndex, print_chat, "%L", playerIndex, "IC_ADMIN_GIVE_MENU_ACCESS_DENIED");
        return PLUGIN_HANDLED;
    }

    if (read_argc() <= Arg_PlayerIndex) {
        menu_display(playerIndex, BuildPlayersMenu(
            .baseCommand = fmt("%s %d", GIVE_COMMAND, menuIndex),
            .menuTitle = fmt("\w%s^n\y%L", menu[GiveMenu_MenuTitle], playerIndex, "IC_ADMIN_GIVE_MENU_CHOOSE_PLAYER_TITLE"),
            .firstPlayerIndex = playerIndex,
            .allItemTitle = fmt("%L", playerIndex, "IC_ADMIN_GIVE_MENU_CHOOSE_PLAYER_ALL"),
            .allItemValue = 0,
            .searchFlags = "ah"
        ));
        return PLUGIN_HANDLED;
    }

    new targetPlayerIndex = read_argv_int(Arg_PlayerIndex);

    if (read_argc() <= Arg_MenuItemIndex) {
        menu_display(playerIndex, BuildItemsMenu(
            .baseCommand = fmt("%s %d %d", GIVE_COMMAND, menuIndex, targetPlayerIndex),
            .menuTitle = fmt(
                "\w%s^n\y%L \w%n^n%L",
                menu[GiveMenu_MenuTitle],
                playerIndex, "IC_ADMIN_GIVE_MENU_CHOSEN_PLAYER_TITLE", targetPlayerIndex,
                playerIndex, "IC_ADMIN_GIVE_MENU_CHOOSE_ITEM_TITLE"
            ),
            .items = menu[GiveMenu_MenuItems]
        ));
        return PLUGIN_HANDLED;
    }

    new itemIndex = read_argv_int(Arg_MenuItemIndex);

    new item[S_GiveMenuItem];
    ArrayGetArray(menu[GiveMenu_MenuItems], itemIndex, item);

    if (targetPlayerIndex == 0) {
        for (new i = 1; i < MAX_PLAYERS; ++i) {
            if (is_user_alive(i)) {
                VipM_IC_GiveItems(i, item[GiveMenuItem_Items]);
            }
        }
    } else {
        if (is_user_alive(targetPlayerIndex)) {
            VipM_IC_GiveItems(targetPlayerIndex, item[GiveMenuItem_Items]);
        }
    }

    return PLUGIN_HANDLED;
}

BuildItemsMenu(
    const menuTitle[],
    const baseCommand[],

    const Array:items
) {
    new menu = menu_create(menuTitle, "@MenuHandler_CommandWithDestroy");

    for (new i = 0, ii = ArraySize(items); i < ii; ++i) {
        new item[S_GiveMenuItem];
        ArrayGetArray(items, i, item);

        menu_additem(menu, item[GiveMenu_Title], fmt("%s %d", baseCommand, i));
    }

    return Menu_SetProps(menu);
}

BuildPlayersMenu(
    const baseCommand[],
    const menuTitle[] = "Выберите игрока:",

    const firstPlayerIndex = 0,

    const allItemTitle[] = "",
    const allItemValue = 0,

    const searchFlags[] = "",
    const searchTeam[] = ""
) {
    new menu = menu_create(menuTitle, "@MenuHandler_CommandWithDestroy");
    
    if (allItemTitle[0] != EOS) {
        menu_additem(menu, fmt("\y%s^n", allItemTitle), fmt("%s %d", baseCommand, allItemValue));
    }
    
    new players[MAX_PLAYERS], playersCount;
    get_players(players, playersCount, searchFlags, searchTeam);

    if (firstPlayerIndex > 0) {
        for (new i = 0; i < playersCount; ++i) {
            if (players[i] == firstPlayerIndex) {
                menu_additem(menu, fmt("\y%n^n", players[i]), fmt("%s %d", baseCommand, players[i]));
            }
        }
    }

    for (new i = 0; i < playersCount; ++i) {
        if (firstPlayerIndex > 0 && players[i] == firstPlayerIndex) {
            continue;
        }

        menu_additem(menu, fmt("%n", players[i]), fmt("%s %d", baseCommand, players[i]));
    }

    return Menu_SetProps(menu);
}

LoadMenusFromFolder(path[]) {
    new file[PLATFORM_MAX_PATH], dirHnd, FileType:fileType;
    dirHnd = open_dir(path, file, charsmax(file), fileType);
    if (!dirHnd) {
        set_fail_state("[ERROR] Can't open folder '%s'.", path);
        return;
    }

    new Regex:fileNameRegex, ret;
    fileNameRegex = regex_compile("(.+).json$", ret, "", 0, "i");

    do {
        if (
            file[0] == '!'
            || fileType != FileType_File
            || regex_match_c(file, fileNameRegex) <= 0
        ) {
            continue;
        }

        regex_substr(fileNameRegex, 1, file, charsmax(file));
        LoadMenuFromFile(fmt("%s/%s.json", path, file));

    } while (next_file(dirHnd, file, charsmax(file), fileType));

    regex_free(fileNameRegex);
    close_dir(dirHnd);
}

LoadMenuFromFile(const path[]) {
    new JSON:menuJson = json_parse(path, true, true);
    new menuIndex = LoadMenuFromJson(menuJson);
    json_free(menuJson);

    return menuIndex;
}

LoadMenuFromJson(const JSON:menuJson) {
    new menu[S_GiveMenu];

    new flags[32];
    json_object_get_string(menuJson, "AccessFlags", flags, charsmax(flags));
    menu[GiveMenu_AccessFlags] = read_flags(flags);

    json_object_get_string(menuJson, "MenuTitle", menu[GiveMenu_MenuTitle], charsmax(menu[GiveMenu_MenuTitle]));

    new JSON:items = json_object_get_value(menuJson, "MenuItems");
    menu[GiveMenu_MenuItems] = ArrayCreate(S_GiveMenuItem, json_array_get_count(items));
    for (new i = 0, ii = json_array_get_count(items); i < ii; ++i) {
        new JSON:itemJson = json_array_get_value(items, i);
        new item[S_GiveMenuItem];

        json_object_get_string(itemJson, "Title", item[GiveMenu_Title], charsmax(item[GiveMenu_Title]));
        item[GiveMenuItem_Items] = VipM_IC_JsonGetItems(json_object_get_value(itemJson, "Items"));

        ArrayPushArray(menu[GiveMenu_MenuItems], item);
    }

    if (g_menus == Invalid_Array) {
        g_menus = ArrayCreate(S_GiveMenu, 1);
    }
    new menuIndex = ArrayPushArray(g_menus, menu);


    if (g_menuCmds == Invalid_Trie) {
        g_menuCmds = TrieCreate();
    }
    new JSON:openCmds = json_object_get_value(menuJson, "OpenCommands");
    for (new i = 0, ii = json_array_get_count(openCmds); i < ii; ++i) {
        new cmd[128];
        json_array_get_string(openCmds, i, cmd, charsmax(cmd));
        TrieSetCell(g_menuCmds, cmd, menuIndex);
        register_clcmd(cmd, "@ClCmd_OpenMenu");
    }

    return menuIndex;
}

// CfgUtils.inc

// Simplificated https://github.com/AmxxModularEcosystem/CustomWeaponsAPI/blob/master/amxmodx/scripting/Cwapi/CfgUtils.inc#L32-L43
CfgUtils_MakePath(const path[]) {
    static __amxx_configsdir[PLATFORM_MAX_PATH];
    if (!__amxx_configsdir[0]) {
        get_localinfo("amxx_configsdir", __amxx_configsdir, charsmax(__amxx_configsdir));
    }

    new out[PLATFORM_MAX_PATH];
    formatex(out, charsmax(out), "%s/plugins/%s/%s", __amxx_configsdir, g_cfgFolder, path);

    return out;
}

// MenuUtils.inc

@MenuHandler_Command(const UserId, const MenuId, const ItemId) {
    if (ItemId == MENU_EXIT) {
        return;
    }

    static sCmd[128];
    menu_item_getinfo(MenuId, ItemId, _, sCmd, charsmax(sCmd));

    if (sCmd[0]) {
        client_cmd(UserId, sCmd);
    }
}

@MenuHandler_CommandWithDestroy(const UserId, const MenuId, const ItemId) {
    @MenuHandler_Command(UserId, MenuId, ItemId);

    menu_destroy(MenuId);
}

Menu_SetProps(
    const iMenu,
    const sExitLabel[] = "Выход",
    const sNextLabel[] = "Далее",
    const sBackLabel[] = "Назад"
) {
    menu_setprop(iMenu, MPROP_EXITNAME, sExitLabel);
    menu_setprop(iMenu, MPROP_NEXTNAME, sNextLabel);
    menu_setprop(iMenu, MPROP_BACKNAME, sBackLabel);

    return iMenu;
}