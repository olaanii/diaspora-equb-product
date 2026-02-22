import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/pool_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/wallet_provider.dart';
import '../services/app_snackbar_service.dart';
import '../services/wallet_service.dart';
import '../config/theme.dart';
import '../config/app_config.dart';

class PoolStatusScreen extends StatefulWidget {
  final String poolId;
  const PoolStatusScreen({super.key, required this.poolId});

  @override
  State<PoolStatusScreen> createState() => _PoolStatusScreenState();
}

class _PoolStatusScreenState extends State<PoolStatusScreen> {
  Map<String, dynamic>? _tokenInfo;
  bool _isContributing = false;
  bool _isJoining = false;
  bool _isBindingIdentity = false;
  bool _isSelectingWinner = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPoolData();
    });
  }

  Future<void> _loadPoolData() async {
    final pools = context.read<PoolProvider>();
    await pools.loadPool(widget.poolId);

    final info = await pools.getPoolTokenInfo(widget.poolId);
    if (mounted) {
      setState(() => _tokenInfo = info);
    }
  }

  bool get _isErc20Pool {
    if (_tokenInfo == null) return false;
    return _tokenInfo!['isErc20'] == true;
  }

  String get _tokenSymbol {
    if (!_isErc20Pool || _tokenInfo?['token'] == null) return 'CTC';
    return _tokenInfo!['token']['symbol'] ?? 'TOKEN';
  }

  String? get _tokenAddress {
    if (!_isErc20Pool || _tokenInfo?['token'] == null) return null;
    return _tokenInfo!['token']['address'];
  }

  String _shortTx(String txHash, {int length = 12}) {
    if (txHash.length <= length) return txHash;
    return txHash.substring(0, length);
  }

  bool _isMemberOfPool(Map<String, dynamic> pool, String? walletAddress) {
    if (walletAddress == null || walletAddress.trim().isEmpty) return false;
    final members = (pool['members'] as List?) ?? const [];
    final me = walletAddress.toLowerCase().trim();
    for (final member in members) {
      final address =
          (member['walletAddress'] ?? '').toString().toLowerCase().trim();
      if (address == me) return true;
    }
    return false;
  }

  /// True if the user is the pool admin: only the wallet that signed pool creation (createdBy).
  /// Treasury does not define admin; only the creation signer does.
  bool _isPoolAdmin(Map<String, dynamic> pool, String? authAddress,
      String? connectedAddress) {
    final createdBy = pool['createdBy']?.toString().trim();
    if (createdBy == null || createdBy.isEmpty) return false;
    const zero = '0x0000000000000000000000000000000000000000';
    if (createdBy.toLowerCase() == zero) return false;
    final creatorLower = createdBy.toLowerCase();
    bool match(String? addr) {
      if (addr == null || addr.isEmpty) return false;
      return addr.toLowerCase().trim() == creatorLower;
    }

    return match(authAddress) || match(connectedAddress);
  }

  Future<void> _closeRoundAndAutoPickWinner(
    PoolProvider pools,
    WalletService wallet,
    String caller,
    Map<String, dynamic> pool,
  ) async {
    final onChainPoolId = pool['onChainPoolId'];
    if (onChainPoolId == null) {
      AppSnackbarService.instance.warning(
        message: 'Pool has no on-chain ID yet.',
        dedupeKey: 'pool_status_missing_onchain_id',
      );
      return;
    }

    final contributionStr = pool['contributionAmount']?.toString() ?? '0';
    final contribWei = int.tryParse(contributionStr) ?? 0;
    final members = pool['members'] as List? ?? [];
    final memberCount = members.length;
    if (memberCount == 0) {
      AppSnackbarService.instance.warning(
        message: 'Pool has no members yet.',
        dedupeKey: 'pool_status_no_members',
      );
      return;
    }

    const upfrontPercent = 20;
    final maxMembers = pool['maxMembers'] ?? 10;
    final totalRounds = maxMembers;
    final totalWei = contribWei * memberCount;
    final total = totalWei.toString();

    setState(() => _isSelectingWinner = true);
    AppSnackbarService.instance.info(
      message: 'Step 1/2: Close round — confirm in wallet...',
      dedupeKey: 'pool_status_select_winner_close_pending',
      duration: const Duration(seconds: 3),
    );
    final result = await pools.buildAndSignSelectWinner(
      poolId: widget.poolId,
      total: total,
      upfrontPercent: upfrontPercent,
      totalRounds: totalRounds,
      caller: caller,
      onProgress: (message) {
        AppSnackbarService.instance.info(
          message: message,
          dedupeKey: 'pool_status_select_winner_progress_$message',
          duration: const Duration(seconds: 3),
        );
      },
    );
    if (!mounted) return;
    setState(() => _isSelectingWinner = false);
    if (result != null) {
      context.read<NotificationProvider>().triggerFastSync();
      final auth = context.read<AuthProvider>();
      if (auth.walletAddress != null) {
        await context
            .read<WalletProvider>()
            .refreshAfterTx(auth.walletAddress!);
      }
      await pools.loadPool(widget.poolId);

      final winner = result['winner']?.toString() ?? '';
      final closeTxHash = result['closeTxHash']?.toString() ?? '';
      final scheduleTxHash = result['scheduleTxHash']?.toString() ?? '';
      final nextAction = result['nextAction']?.toString() ?? '';
      final warning = result['warning']?.toString() ?? '';

      if (!mounted) return;
      if (scheduleTxHash.isNotEmpty) {
        AppSnackbarService.instance.success(
          message:
              'Winner scheduled: ${_truncateAddress(winner)}. Close TX: ${_shortTx(closeTxHash)}... Schedule TX: ${_shortTx(scheduleTxHash)}...',
          dedupeKey: 'pool_status_select_winner_success_$scheduleTxHash',
          duration: const Duration(seconds: 4),
          actionLabel: 'View',
          onAction: () {
            debugPrint('${AppConfig.explorerUrl}/tx/$scheduleTxHash');
          },
        );
      } else {
        final winnerText =
            winner.isNotEmpty ? ' Winner: ${_truncateAddress(winner)}.' : '';
        final needsUpgradePath = nextAction.contains('upgrade_contract');
        if (needsUpgradePath) {
          AppSnackbarService.instance.error(
            message:
                'Round closed (TX: ${_shortTx(closeTxHash)}...).$winnerText ${warning.isNotEmpty ? warning : 'Winner scheduling is unavailable on this deployed contract version.'}',
            dedupeKey: 'pool_status_select_winner_upgrade_$closeTxHash',
            duration: const Duration(seconds: 5),
          );
        } else {
          AppSnackbarService.instance.warning(
            message:
                'Round closed (TX: ${_shortTx(closeTxHash)}...).$winnerText Waiting for payout transaction readiness. Please tap Select Winner again in a few seconds.',
            dedupeKey: 'pool_status_select_winner_wait_$closeTxHash',
            duration: const Duration(seconds: 5),
          );
        }

        if (nextAction.isNotEmpty) {
          debugPrint('Select-winner nextAction: $nextAction');
        }
      }
    } else {
      AppSnackbarService.instance.error(
        message:
            pools.errorMessage ?? 'Auto winner selection failed or was rejected',
        dedupeKey: 'pool_status_select_winner_failed',
      );
    }
  }

  Future<void> _contributeOnChain(
    PoolProvider pools,
    WalletService wallet,
    Map<String, dynamic> pool,
  ) async {
    final onChainPoolId = pool['onChainPoolId'];
    final contributionAmount = pool['contributionAmount'] ?? '0';

    if (onChainPoolId == null) {
      AppSnackbarService.instance.warning(
        message: 'Pool has no on-chain ID yet.',
        dedupeKey: 'pool_status_missing_onchain_id_contribute',
      );
      return;
    }

    setState(() => _isContributing = true);

    AppSnackbarService.instance.info(
      message: _isErc20Pool
          ? 'Step 1/2: Approve $_tokenSymbol spending — confirm in wallet...'
          : 'Contributing $contributionAmount — confirm in your wallet...',
      dedupeKey: 'pool_status_contribute_pending',
      duration: const Duration(seconds: 3),
    );

    String? txHash;

    if (_isErc20Pool && _tokenAddress != null) {
      txHash = await pools.approveAndContribute(
        onChainPoolId: onChainPoolId as int,
        contributionAmount: contributionAmount.toString(),
        tokenAddress: _tokenAddress!,
      );
    } else {
      txHash = await pools.buildAndSignContribute(
        onChainPoolId as int,
        contributionAmount.toString(),
        tokenAddress: _tokenAddress,
        poolId: widget.poolId,
      );
    }

    if (!mounted) return;
    setState(() => _isContributing = false);

    if (txHash != null) {
      context.read<NotificationProvider>().triggerFastSync();
      final auth = context.read<AuthProvider>();
      if (auth.walletAddress != null) {
        await context.read<WalletProvider>().refreshAfterTx(
              auth.walletAddress!,
            );
      }
      if (!mounted) return;
      await pools.loadPool(widget.poolId);
      if (!mounted) return;

      AppSnackbarService.instance.success(
        message: 'Contribution confirmed! TX: ${txHash.substring(0, 16)}...',
        dedupeKey: 'pool_status_contribute_success_$txHash',
        duration: const Duration(seconds: 4),
        actionLabel: 'View',
        onAction: () {
          debugPrint('${AppConfig.explorerUrl}/tx/$txHash');
        },
      );
    } else {
      final err = pools.errorMessage ?? 'Contribution failed or rejected';
      AppSnackbarService.instance.error(
        message:
            '$err\nTip: Join the pool first, contribute once per round, and use the Contribute button (not a direct send to the pool address).',
        dedupeKey: 'pool_status_contribute_failed',
        duration: const Duration(seconds: 6),
      );
    }
  }

  Future<void> _joinPoolOnChain(
    PoolProvider pools,
    WalletService wallet,
    Map<String, dynamic> pool,
  ) async {
    final onChainPoolId = pool['onChainPoolId'];
    if (onChainPoolId == null) {
      AppSnackbarService.instance.warning(
        message: 'Pool has no on-chain ID yet.',
        dedupeKey: 'pool_status_missing_onchain_id_join',
      );
      return;
    }

    setState(() => _isJoining = true);
    AppSnackbarService.instance.info(
      message: 'Joining pool — confirm in your wallet...',
      dedupeKey: 'pool_status_join_pending',
      duration: const Duration(seconds: 3),
    );

    final caller = wallet.walletAddress;
    final txHash = await pools.buildAndSignJoinPool(
      onChainPoolId as int,
      caller: caller,
    );
    if (!mounted) return;
    setState(() => _isJoining = false);

    if (txHash != null) {
      context.read<NotificationProvider>().triggerFastSync();
      final auth = context.read<AuthProvider>();
      if (auth.walletAddress != null) {
        await context
            .read<WalletProvider>()
            .refreshAfterTx(auth.walletAddress!);
      }
      await pools.loadPool(widget.poolId);
      if (!mounted) return;

      AppSnackbarService.instance.success(
        message:
            'Joined pool successfully! TX: ${_shortTx(txHash, length: 16)}...',
        dedupeKey: 'pool_status_join_success_$txHash',
        duration: const Duration(seconds: 4),
        actionLabel: 'View',
        onAction: () => debugPrint('${AppConfig.explorerUrl}/tx/$txHash'),
      );
    } else {
      final err = pools.errorMessage ?? 'Join failed or rejected';
      final isIdentityNotBound =
          err.toLowerCase().contains('identity is not bound on-chain');
      AppSnackbarService.instance.error(
        message:
            '$err\nTip: Make sure your wallet is identity-verified and the pool still has open member slots.',
        dedupeKey: 'pool_status_join_failed',
        duration: const Duration(seconds: 6),
        actionLabel: isIdentityNotBound ? 'Bind Now' : null,
        onAction: isIdentityNotBound
            ? () {
                final auth = context.read<AuthProvider>();
                _bindIdentityOnChain(auth);
              }
            : null,
      );
    }
  }

  Future<void> _bindIdentityOnChain(AuthProvider auth) async {
    if (_isBindingIdentity) return;

    setState(() => _isBindingIdentity = true);
    AppSnackbarService.instance.info(
      message: 'Binding identity on-chain — confirm in wallet...',
      dedupeKey: 'pool_status_bind_identity_pending',
      duration: const Duration(seconds: 3),
    );

    final txHash = await auth.bindIdentityOnChain();
    if (!mounted) return;
    setState(() => _isBindingIdentity = false);

    if (txHash != null) {
      context.read<NotificationProvider>().triggerFastSync();
      if (auth.walletAddress != null) {
        await context
            .read<WalletProvider>()
            .refreshAfterTx(auth.walletAddress!);
      }
      if (!mounted) return;
      AppSnackbarService.instance.success(
        message:
            'Identity bound on-chain. TX: ${_shortTx(txHash, length: 16)}... You can now join the pool.',
        dedupeKey: 'pool_status_bind_identity_success_$txHash',
        duration: const Duration(seconds: 5),
        actionLabel: 'View',
        onAction: () => debugPrint('${AppConfig.explorerUrl}/tx/$txHash'),
      );
    } else {
      AppSnackbarService.instance.error(
        message:
            auth.errorMessage ?? 'Identity binding failed or was rejected.',
        dedupeKey: 'pool_status_bind_identity_failed',
        duration: const Duration(seconds: 6),
      );
    }
  }

  Future<void> _handleContributePressed(
    PoolProvider pools,
    WalletService wallet,
    Map<String, dynamic> pool,
    bool isMember,
  ) async {
    if (isMember) {
      await _contributeOnChain(pools, wallet, pool);
      return;
    }

    final shouldJoin = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Join Required'),
          content: const Text(
            'You need to join this pool before contributing. Do you want to join now?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Join Now'),
            ),
          ],
        );
      },
    );

    if (shouldJoin == true && mounted) {
      await _joinPoolOnChain(pools, wallet, pool);
    }
  }

  Future<void> _contributeLegacy(
    PoolProvider pools,
    String walletAddress,
    Map<String, dynamic> pool,
  ) async {
    final round = pool['currentRound'] ?? 1;
    final success = await pools.contribute(
      widget.poolId,
      walletAddress,
      round,
    );
    if (mounted) {
      if (success) {
        AppSnackbarService.instance.success(
          message: 'Contribution recorded for round $round!',
          dedupeKey: 'pool_status_legacy_contribute_success_$round',
        );
      } else {
        AppSnackbarService.instance.error(
          message: pools.errorMessage ?? 'Contribution failed',
          dedupeKey: 'pool_status_legacy_contribute_failed',
        );
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    final pools = context.watch<PoolProvider>();
    final auth = context.watch<AuthProvider>();
    final wallet = context.watch<WalletService>();
    final walletProvider = context.watch<WalletProvider>();
    final pool = pools.selectedPool;

    return Container(
      decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Pool Status'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh pool (e.g. after on-chain creation)',
              onPressed: () async {
                await _loadPoolData();
              },
            ),
            IconButton(
              icon: const Icon(Icons.payment),
              tooltip: 'View Payout Stream',
              onPressed: () => context.push('/payouts/${widget.poolId}'),
            ),
          ],
        ),
        body: pool == null
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadPoolData,
                child: Builder(
                  builder: (context) {
                    // Pool admin = who signed pool creation (createdBy) or treasury as fallback.
                    final isPoolAdmin = _isPoolAdmin(
                        pool, auth.walletAddress, wallet.walletAddress);
                    final connectedOrAuthAddress =
                        auth.walletAddress ?? wallet.walletAddress;
                    final isMember =
                        _isMemberOfPool(pool, connectedOrAuthAddress);
                    final members = (pool['members'] as List?) ?? const [];
                    final memberCount = members.length;
                    final maxMembers =
                        int.tryParse('${pool['maxMembers'] ?? 0}') ?? 0;
                    final hasOpenSlots =
                        maxMembers == 0 || memberCount < maxMembers;
                    final creatorCaller =
                        auth.walletAddress ?? wallet.walletAddress;
                    final canRunDraw = isPoolAdmin &&
                        pool['onChainPoolId'] != null &&
                        wallet.isConnected;
                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        // Pool header card
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Tier ${pool['tier'] ?? 0}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                              fontWeight: FontWeight.bold),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: AppTheme.successColor
                                            .withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        pool['status'] ?? 'pending',
                                        style: const TextStyle(
                                          color: AppTheme.successColor,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 24),
                                _buildInfoRow('Contribution',
                                    '${pool['contributionAmount'] ?? '0'} wei'),
                                _buildInfoRow('Current Round',
                                    '${pool['currentRound'] ?? 1}'),
                                _buildInfoRow('Treasury',
                                    _truncateAddress(pool['treasury'] ?? '')),
                                if (pool['createdBy'] != null &&
                                    (pool['createdBy'] as String).isNotEmpty &&
                                    (pool['createdBy'] as String)
                                            .toLowerCase() !=
                                        '0x0000000000000000000000000000000000000000')
                                  _buildInfoRow(
                                      'Creator (pool admin)',
                                      _truncateAddress(
                                          pool['createdBy'] ?? '')),
                                if (pool['onChainPoolId'] != null)
                                  _buildInfoRow('On-Chain ID',
                                      '${pool['onChainPoolId']}'),
                                if (_isErc20Pool)
                                  _buildInfoRow('Token',
                                      '$_tokenSymbol ($_tokenAddress)'),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Pool admin: show for on-chain pools or when you are the creator
                        if (pool['onChainPoolId'] != null || isPoolAdmin) ...[
                          Card(
                            color:
                                AppTheme.primaryColor.withValues(alpha: 0.06),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Pool admin',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: canRunDraw &&
                                              !_isSelectingWinner &&
                                              !pools.isLoading &&
                                              creatorCaller != null
                                          ? () => _closeRoundAndAutoPickWinner(
                                                pools,
                                                wallet,
                                                creatorCaller,
                                                pool,
                                              )
                                          : null,
                                      icon: _isSelectingWinner
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(Icons.flag_outlined,
                                              size: 20),
                                      label: Text(
                                        _isSelectingWinner
                                            ? 'Processing round + winner...'
                                            : 'Close round & Auto-pick rotating winner',
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppTheme.primaryColor,
                                        side: const BorderSide(
                                            color: AppTheme.primaryColor),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    canRunDraw
                                        ? 'One click closes the round and auto-selects the next winner by Equb rotation (not manual random pick).'
                                        : 'Only the creator wallet can run automatic winner rotation.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  if (!canRunDraw) ...[
                                    const SizedBox(height: 8),
                                    if (!wallet.isConnected)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 6),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Icon(
                                                Icons.warning_amber_rounded,
                                                size: 18,
                                                color: AppTheme.warningColor),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'Connect your wallet to enable automatic close + winner selection.',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (wallet.isConnected && !isPoolAdmin)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Icon(Icons.info_outline,
                                                size: 18,
                                                color: AppTheme.warningColor),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'Only the wallet that signed pool creation can run automatic Equb winner selection.',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Balance card showing deduction preview
                        if (auth.walletAddress != null &&
                            wallet.isConnected) ...[
                          _buildBalancePreviewCard(walletProvider, pool),
                          const SizedBox(height: 16),
                        ],

                        // Members section
                        Text(
                          'Members (${(pool['members'] as List?)?.length ?? 0}/${pool['maxMembers'] ?? 0})',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        ...((pool['members'] as List?) ?? [])
                            .map<Widget>((member) {
                          final address = member['walletAddress'] ?? '';
                          final isCurrentUser = address == auth.walletAddress;
                          return Card(
                            color: isCurrentUser
                                ? AppTheme.primaryColor.withValues(alpha: 0.05)
                                : null,
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isCurrentUser
                                    ? AppTheme.primaryColor
                                    : Colors.grey[300],
                                child: Icon(
                                  Icons.person,
                                  color: isCurrentUser
                                      ? Colors.white
                                      : Colors.grey[600],
                                ),
                              ),
                              title: Text(
                                _truncateAddress(address),
                                style: const TextStyle(fontFamily: 'monospace'),
                              ),
                              subtitle: Text(
                                isCurrentUser ? 'You' : 'Member',
                                style: TextStyle(
                                  color: isCurrentUser
                                      ? AppTheme.primaryColor
                                      : Colors.grey[600],
                                ),
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 24),

                        // Contribute buttons
                        if (auth.walletAddress != null) ...[
                          if (wallet.isConnected &&
                              pool['onChainPoolId'] != null) ...[
                            if (!isMember) ...[
                              SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: OutlinedButton.icon(
                                  onPressed: (_isBindingIdentity ||
                                          _isJoining ||
                                          _isContributing ||
                                          pools.isLoading)
                                      ? null
                                      : () => _bindIdentityOnChain(auth),
                                  icon: _isBindingIdentity
                                      ? const SizedBox(
                                          height: 18,
                                          width: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.verified_user_outlined,
                                          size: 20,
                                        ),
                                  label: Text(
                                    _isBindingIdentity
                                        ? 'Binding Identity On-Chain...'
                                        : 'Bind Identity On-Chain',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppTheme.primaryColor,
                                    side: const BorderSide(
                                      color: AppTheme.primaryColor,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(26),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                height: 56,
                                child: ElevatedButton.icon(
                                  onPressed: (_isJoining ||
                                          _isContributing ||
                                          pools.isLoading ||
                                          !hasOpenSlots)
                                      ? null
                                      : () => _joinPoolOnChain(
                                            pools,
                                            wallet,
                                            pool,
                                          ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryColor,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(28),
                                    ),
                                    elevation: 0,
                                  ),
                                  icon: _isJoining
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.group_add_outlined,
                                          size: 20),
                                  label: Text(
                                    !hasOpenSlots
                                        ? 'Pool Full'
                                        : (_isJoining
                                            ? 'Joining Pool...'
                                            : 'Join Pool'),
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],
                            SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: ElevatedButton(
                                onPressed: (_isContributing ||
                                        _isJoining ||
                                        pools.isLoading ||
                                        (!isMember && !hasOpenSlots))
                                    ? null
                                    : () => _handleContributePressed(
                                          pools,
                                          wallet,
                                          pool,
                                          isMember,
                                        ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.darkButton,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(28),
                                  ),
                                  elevation: 0,
                                ),
                                child: _isContributing
                                    ? const SizedBox(
                                        height: 24,
                                        width: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                              Icons
                                                  .account_balance_wallet_outlined,
                                              size: 20),
                                          const SizedBox(width: 10),
                                          Text(
                                            isMember
                                                ? (_isErc20Pool
                                                    ? 'Approve & Contribute $_tokenSymbol (Round ${pool['currentRound'] ?? 1})'
                                                    : 'Contribute On-Chain (Round ${pool['currentRound'] ?? 1})')
                                                : (_isJoining
                                                    ? 'Joining Pool...'
                                                    : 'Join Pool to Contribute'),
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              isMember
                                  ? (_isErc20Pool
                                      ? 'Two wallet signatures required: approve $_tokenSymbol spend, then contribute.'
                                      : 'Your wallet (MetaMask) will pop up to sign this transaction.')
                                  : 'If join fails, bind identity on-chain first, then join and contribute.',
                              style: const TextStyle(
                                color: AppTheme.textTertiary,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              !hasOpenSlots && !isMember
                                  ? 'This pool is full. No additional members can join.'
                                  : 'Join first (if needed), then use the Contribute button. Do not send tCTC directly to the pool address—it will fail.',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 11,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ] else ...[
                            ElevatedButton.icon(
                              onPressed: () => _contributeLegacy(
                                pools,
                                auth.walletAddress!,
                                pool,
                              ),
                              icon: const Icon(Icons.payment),
                              label: Text(
                                'Contribute to Round ${pool['currentRound'] ?? 1}',
                              ),
                            ),
                            if (!wallet.isConnected)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  'Connect WalletConnect for on-chain contributions',
                                  style: TextStyle(
                                      color: Colors.grey[500], fontSize: 12),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                          ],
                        ],

                        // Last TX hash
                        if (pools.lastTxHash != null) ...[
                          const SizedBox(height: 16),
                          Card(
                            color:
                                AppTheme.successColor.withValues(alpha: 0.05),
                            child: ListTile(
                              leading: const Icon(Icons.check_circle,
                                  color: AppTheme.successColor),
                              title: const Text('Last Transaction'),
                              subtitle: Text(
                                pools.lastTxHash!,
                                style: const TextStyle(
                                    fontFamily: 'monospace', fontSize: 11),
                              ),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
      ),
    );
  }

  Widget _buildBalancePreviewCard(
      WalletProvider walletProvider, Map<String, dynamic> pool) {
    final contributionRaw = pool['contributionAmount']?.toString() ?? '0';
    final contribution = double.tryParse(contributionRaw) ?? 0;

    String currentBalance;
    String afterBalance;

    if (_isErc20Pool) {
      final bal = double.tryParse(walletProvider.balanceOf(_tokenSymbol)) ?? 0;
      currentBalance = bal.toStringAsFixed(2);
      afterBalance = (bal - contribution).toStringAsFixed(2);
    } else {
      final bal = double.tryParse(walletProvider.balance) ?? 0;
      currentBalance = bal.toStringAsFixed(2);
      afterBalance = (bal - contribution).toStringAsFixed(2);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.accentYellow.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppTheme.cardRadiusSmall),
        border: Border.all(
          color: AppTheme.accentYellow,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Your Balance',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textSecondary,
                ),
              ),
              Text(
                '\$$currentBalance ${_isErc20Pool ? _tokenSymbol : 'CTC'}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Contribution',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.negative,
                ),
              ),
              Text(
                '-$contributionRaw',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.negative,
                ),
              ),
            ],
          ),
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'After Contribution',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              Text(
                '\$$afterBalance',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _truncateAddress(String address) {
    if (address.length < 10) return address;
    return '${address.substring(0, 8)}...${address.substring(address.length - 6)}';
  }
}
