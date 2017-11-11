stock void Chat(int client, const char[] message, any ...)
{
	if (!(1 <= client <= MaxClients) || !IsClientInGame(client))
	{
		return;
	}

	char buffer[1024];
	VFormat(buffer, 1024, message, 3);
	SendMessage(client, buffer);
}

stock void ChatAll(const char[] message, any ...)
{
	char buffer[1024];
	for (int client = 1; client < MaxClients; client++)
	{
		if (!IsClientInGame(client))
		{
			continue;
		}

		VFormat(buffer, 1024, message, 2);
		SendMessage(client, buffer);
	}
}

stock void SendMessage(int client, const char[] message, int author = 0)
{
	if (GetFeatureStatus(FeatureType_Native, "GetUserMessageType") != FeatureStatus_Available)
	{
		PrintToChat(client, message);

		return;
	}

	if (author == 0)
	{
		author = client;
	}

	Handle msg = StartMessageOne("SayText2", client, USERMSG_RELIABLE|USERMSG_BLOCKHOOKS);

	if (GetUserMessageType() == UM_Protobuf)
	{
		Protobuf pb = UserMessageToProtobuf(msg);

		pb.SetInt("ent_idx", author);
		pb.SetBool("chat", true);
		pb.SetString("msg_name", message);
		pb.AddString("params", "");
		pb.AddString("params", "");
		pb.AddString("params", "");
		pb.AddString("params", "");
	}
	else
	{
		BfWrite bf = UserMessageToBfWrite(msg);

		bf.WriteByte(author);
		bf.WriteByte(true);
		bf.WriteString(message);
	}

	EndMessage();
}