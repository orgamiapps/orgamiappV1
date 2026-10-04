import 'package:attendus/screens/Messaging/chat_screen.dart' deferred as chat;
import 'package:attendus/widgets/deferred_screen_loader.dart';
import 'package:flutter/material.dart';

class DeferredConversationScreen extends StatelessWidget {
  final String conversationId;
  const DeferredConversationScreen({super.key, required this.conversationId});

  @override
  Widget build(BuildContext context) => DeferredScreenLoader(
    loadLibrary: chat.loadLibrary,
    recoveryKey: 'conversation',
    loadingLabel: 'Opening conversation',
    builder: () => chat.ChatScreen(conversationId: conversationId),
  );
}
