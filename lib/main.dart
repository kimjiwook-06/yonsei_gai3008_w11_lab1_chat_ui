import 'package:flutter/material.dart';

void main() => runApp(const ChatLabApp());

class ChatLabApp extends StatelessWidget {
  const ChatLabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Chat — 실습 1 · 4',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2F6FE4)),
        useMaterial3: true,
      ),
      home: const ChatPage(),
    );
  }
}

sealed class _ChatEntry {
  const _ChatEntry();
}

class ChatMessage extends _ChatEntry {
  const ChatMessage({required this.text, required this.isUser});

  final String text;
  final bool isUser;
}

enum _ChatFailure {
  unauthorized('401', '인증에 실패했어요.'),
  rateLimited('429', '요청이 너무 많아요. 잠시 후 다시 시도해 주세요.'),
  server('500', '서버에서 오류가 발생했어요.'),
  timeout('Timeout', '응답 시간이 초과됐어요.');

  const _ChatFailure(this.label, this.message);

  final String label;
  final String message;
}

enum _DemoScenario {
  normal('정상 응답'),
  unauthorized('401 오류', failure: _ChatFailure.unauthorized),
  rateLimited('429 오류', failure: _ChatFailure.rateLimited),
  rateLimitRecovery(
    '429 후 정상 응답',
    failure: _ChatFailure.rateLimited,
    failuresBeforeRecovery: 2,
  ),
  server('500 오류', failure: _ChatFailure.server),
  timeout('Timeout 오류', failure: _ChatFailure.timeout);

  const _DemoScenario(this.label, {this.failure, this.failuresBeforeRecovery});

  final String label;
  final _ChatFailure? failure;
  final int? failuresBeforeRecovery;
}

class _ChatReply extends _ChatEntry {
  _ChatReply(this.prompt);

  final String prompt;
  String? answer;
  _ChatFailure? failure;
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, this.initialMessages = _defaultMessages});

  final List<ChatMessage> initialMessages;

  static const List<ChatMessage> _defaultMessages = [
    ChatMessage(text: '오늘 뭐 배워?', isUser: true),
    ChatMessage(text: 'AI 챗봇에 움직이는 응답을 붙입니다.', isUser: false),
    ChatMessage(text: '타이핑 점은 왜 필요해요?', isUser: true),
    ChatMessage(text: '응답이 1초를 넘으면 앱이 멈춘 것처럼 보이기 때문입니다.', isUser: false),
  ];

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late final List<_ChatEntry> _messages = [...widget.initialMessages];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  _DemoScenario _scenario = _DemoScenario.normal;
  bool _sending = false;

  static const _rateLimitDelays = [Duration(seconds: 1), Duration(seconds: 2)];

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (_sending || text.isEmpty) return;

    final reply = _ChatReply(text);
    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _messages.add(reply);
    });
    _controller.clear();
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    await _loadReply(reply, _scenario);
  }

  Future<void> _loadReply(_ChatReply reply, _DemoScenario scenario) async {
    if (_sending) return;
    setState(() {
      _sending = true;
      reply.failure = null;
    });

    for (var attempt = 0; ; attempt++) {
      try {
        final answer = await _requestDemoReply(reply.prompt, scenario, attempt);
        if (!mounted) return;
        setState(() {
          reply.answer = answer;
          _sending = false;
        });
        return;
      } on _ChatFailure catch (failure) {
        if (!mounted) return;
        if (failure == _ChatFailure.rateLimited &&
            attempt < _rateLimitDelays.length) {
          await Future<void>.delayed(_rateLimitDelays[attempt]);
          if (!mounted) return;
          continue;
        }
        setState(() {
          reply.failure = failure;
          _sending = false;
        });
        return;
      }
    }
  }

  // 서버 없이 정상 응답과 각 오류를 재현한다.
  Future<String> _requestDemoReply(
    String prompt,
    _DemoScenario scenario,
    int attempt,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    final failure = scenario.failure;
    final failuresBeforeRecovery = scenario.failuresBeforeRecovery;
    if (failure != null &&
        (failuresBeforeRecovery == null || attempt < failuresBeforeRecovery)) {
      throw failure;
    }
    return '메시지를 받았어요.\n“$prompt”';
  }

  void _startNewChat() {
    setState(_messages.clear);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('AI Chat — 실습 1 · 4'),
        actions: [
          IconButton(
            onPressed: _sending ? null : _startNewChat,
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: '새 대화',
          ),
          PopupMenuButton<_DemoScenario>(
            enabled: !_sending,
            tooltip: '응답 시나리오',
            icon: const Icon(Icons.science_outlined),
            onSelected: (scenario) => setState(() => _scenario = scenario),
            itemBuilder: (context) => [
              for (final scenario in _DemoScenario.values)
                CheckedPopupMenuItem(
                  value: scenario,
                  checked: _scenario == scenario,
                  child: Text(scenario.label),
                ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      // reverse 목록의 index 0은 화면 맨 아래다.
                      final entry = _messages[_messages.length - 1 - index];
                      return switch (entry) {
                        ChatMessage() => _buildMessage(entry),
                        _ChatReply() => _buildReply(
                          entry,
                          isLatest: index == 0,
                        ),
                      };
                    },
                  ),
                  if (_messages.isEmpty) const _EmptyState(),
                ],
              ),
            ),
            _buildInputBar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildMessage(ChatMessage message, {Key? key}) {
    final colors = Theme.of(context).colorScheme;
    return _Bubble(
      key: key,
      isUser: message.isUser,
      background: message.isUser
          ? colors.primaryContainer
          : colors.surfaceContainerHighest,
      child: Text(
        message.text,
        style: TextStyle(
          color: message.isUser ? colors.onPrimaryContainer : colors.onSurface,
        ),
      ),
    );
  }

  Widget _buildReply(_ChatReply reply, {required bool isLatest}) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedSwitcher(
      key: ObjectKey(reply),
      duration: const Duration(milliseconds: 220),
      child: switch ((reply.failure, reply.answer)) {
        (final _ChatFailure error, _) => _Bubble(
          key: const ValueKey('error'),
          background: colors.errorContainer,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${error.label} · ${error.message}',
                style: TextStyle(color: colors.onErrorContainer),
              ),
              if (isLatest)
                TextButton.icon(
                  // 수동 재시도에서는 같은 메시지의 복구를 재현한다.
                  onPressed: _sending
                      ? null
                      : () => _loadReply(reply, _DemoScenario.normal),
                  icon: const Icon(Icons.refresh),
                  label: const Text('다시 시도'),
                ),
            ],
          ),
        ),
        (_, final String text) => _buildMessage(
          ChatMessage(text: text, isUser: false),
          key: const ValueKey('answer'),
        ),
        _ => _Bubble(
          key: const ValueKey('waiting'),
          background: colors.surfaceContainerHighest,
          child: const Text('응답을 기다리는 중…'),
        ),
      },
    );
  }

  Widget _buildInputBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: '메시지를 입력하세요',
                isDense: true,
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _sending ? null : _send,
            tooltip: '전송',
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    super.key,
    this.isUser = false,
    required this.background,
    required this.child,
  });

  final bool isUser;
  final Color background;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
        ),
        child: child,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 48, color: colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              '무엇이든 물어보세요',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '아래 입력창에 질문을 적어 보세요.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
