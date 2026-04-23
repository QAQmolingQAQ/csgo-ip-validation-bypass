#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

public Plugin myinfo = 
{
    name = "CS:GO Steam Auth Bypass",
    author = "QAQmolingQAQ",
    description = "Bypass Steam auth failure (Code 10) disconnect for FRP connections",
    version = "1.2",
    url = "https://github.com/QAQmolingQAQ/CSGO-Steam-Auth-Bypass"
};

enum struct mem_patch
{
    Address addr;
    int len;
    char patch[256];
    char orig[256];

    bool Init(GameData conf, const char[] key, Address baseAddr)
    {
        int offset, pos, curPos;
        char byte[16], bytes[512];
        
        if (this.len)
            return false;
        
        if (!conf.GetKeyValue(key, bytes, sizeof(bytes)))
            return false;
        
        offset = conf.GetOffset(key);
        if (offset == -1)
            offset = 0;
        
        this.addr = baseAddr + view_as<Address>(offset);
        
        StrCat(bytes, sizeof(bytes), " ");
        
        while ((pos = SplitString(bytes[curPos], " ", byte, sizeof(byte))) != -1)
        {
            curPos += pos;
            TrimString(byte);
            
            if (byte[0])
            {
                this.patch[this.len] = StringToInt(byte, 16);
                this.orig[this.len] = LoadFromAddress(this.addr + view_as<Address>(this.len), NumberType_Int8);
                this.len++;
            }
        }
        
        return true;
    }
    
    void Apply()
    {
        for (int i = 0; i < this.len; i++)
            StoreToAddress(this.addr + view_as<Address>(i), this.patch[i], NumberType_Int8);
    }
    
    void Restore()
    {
        for (int i = 0; i < this.len; i++)
            StoreToAddress(this.addr + view_as<Address>(i), this.orig[i], NumberType_Int8);
    }
}

mem_patch g_AuthBypassPatch;

public void OnPluginStart()
{
    GameData conf = new GameData("ip_fix.games");
    if (!conf) 
        SetFailState("Failed to load ip_fix gamedata");
    
    Address authCallbackAddr = conf.GetAddress("AuthFailureCallback");
    if (!authCallbackAddr)
        SetFailState("Failed to get AuthFailureCallback address from gamedata");
    
    g_AuthBypassPatch.Init(conf, "AuthBypass_Patch", authCallbackAddr);
    g_AuthBypassPatch.Apply();
    
    LogMessage("[SteamAuthBypass] Patch applied at 0x%X (offset +0x8D)", authCallbackAddr);
    delete conf;
}

public void OnPluginEnd()
{
    g_AuthBypassPatch.Restore();
    LogMessage("[SteamAuthBypass] Patch restored");
}