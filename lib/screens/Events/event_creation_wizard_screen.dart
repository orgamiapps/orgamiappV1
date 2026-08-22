import 'dart:async';
import 'package:attendus/models/check_in_policy.dart';
import 'package:attendus/models/discovery_category.dart';
import 'package:attendus/models/event_model.dart';
import 'package:attendus/models/event_wizard_model.dart';
import 'package:attendus/Services/event_wizard_service.dart';
import 'package:attendus/Services/product_funnel_service.dart';
import 'package:attendus/Utils/attendus_theme.dart';
import 'package:attendus/firebase/organization_helper.dart';
import 'package:attendus/firebase/firebase_firestore_helper.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:attendus/screens/Events/location_picker_screen.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class EventCreationWizardScreen extends StatefulWidget {
  const EventCreationWizardScreen({
    super.key,
    this.selectedDateTime,
    this.eventDurationHours,
    this.preselectedOrganizationId,
    this.forceOrganizationEvent = false,
    this.event,
    this.initialDraft,
    this.service,
  });

  final DateTime? selectedDateTime;
  final int? eventDurationHours;
  final String? preselectedOrganizationId;
  final bool forceOrganizationEvent;
  final EventModel? event;
  final EventWizardDraft? initialDraft;
  final EventWizardRepository? service;

  @override
  State<EventCreationWizardScreen> createState() =>
      _EventCreationWizardScreenState();
}

class _EventCreationWizardScreenState extends State<EventCreationWizardScreen>
    with WidgetsBindingObserver {
  late EventWizardDraft _draft;
  late EventWizardRepository _service;
  final ProductFunnelService _funnel = ProductFunnelService();
  final _formKey = GlobalKey<FormState>();
  final _titleFocus = FocusNode();
  final _locationFocus = FocusNode();
  final _scrollController = ScrollController();
  Timer? _autosaveTimer;
  EventWizardSaveState _saveState = EventWizardSaveState.idle;
  bool _publishing = false;
  bool _showPreview = true;
  bool _advancedAttendance = false;
  bool _loadingDrafts = false;
  List<EventWizardDraft> _availableDrafts = const [];
  List<Map<String, String>> _organizations = const [];
  List<Map<String, dynamic>> _savedTemplates = const [];
  Uint8List? _pendingImage;

  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _onlineLocationController;
  late final TextEditingController _capacityController;
  late final TextEditingController _priceController;
  late final TextEditingController _refundController;
  late final TextEditingController _accessibilityController;
  late final TextEditingController _thingsController;
  late final TextEditingController _contactNameController;
  late final TextEditingController _contactEmailController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _service = widget.service ?? EventWizardService();
    _draft =
        widget.initialDraft ??
        (widget.event != null
            ? EventWizardDraft.fromEvent(widget.event!)
            : EventWizardDraft.blank(
                selectedDateTime: widget.selectedDateTime,
                durationHours: widget.eventDurationHours ?? 1,
                organizationId: widget.preselectedOrganizationId,
                forcePrivate: widget.forceOrganizationEvent,
              ));
    _titleController = TextEditingController(text: _draft.title);
    _descriptionController = TextEditingController(text: _draft.description);
    _onlineLocationController = TextEditingController(
      text: _draft.locationType == 'online' ? _draft.location : '',
    );
    _capacityController = TextEditingController(
      text: _draft.capacity?.toString() ?? '',
    );
    _priceController = TextEditingController(
      text: _draft.priceUsd > 0 ? _draft.priceUsd.toStringAsFixed(2) : '',
    );
    _refundController = TextEditingController(text: _draft.refundTerms);
    _accessibilityController = TextEditingController(
      text: _draft.accessibilityDetails,
    );
    _thingsController = TextEditingController(
      text: _draft.thingsToBring.join(', '),
    );
    _contactNameController = TextEditingController(
      text: _draft.publicContactName,
    );
    _contactEmailController = TextEditingController(
      text: _draft.publicContactEmail,
    );
    for (final controller in [
      _titleController,
      _descriptionController,
      _onlineLocationController,
      _capacityController,
      _priceController,
      _refundController,
      _accessibilityController,
      _thingsController,
      _contactNameController,
      _contactEmailController,
    ]) {
      controller.addListener(_onFieldChanged);
    }
    unawaited(
      _funnel.record(
        'event_wizard_started',
        dimensions: {
          'mode': _draft.mode,
          'platform': defaultTargetPlatform.name,
          'organizationContext': _draft.organizationId == null
              ? 'personal'
              : 'group',
          'experienceVersion': '2',
        },
      ),
    );
    unawaited(_loadOrganizations());
    unawaited(_loadSavedTemplates());
    _recordStageView();
  }

  void _recordStageView() {
    unawaited(
      _funnel.record(
        'event_wizard_stage_viewed',
        dimensions: {'stage': _draft.currentStage.name, 'mode': _draft.mode},
      ),
    );
  }

  Future<void> _loadOrganizations() async {
    try {
      final organizations = await OrganizationHelper()
          .getUserOrganizationsLite();
      if (mounted) setState(() => _organizations = organizations);
    } catch (_) {
      // Personal hosting and any preselected organization remain available.
    }
  }

  Future<void> _loadSavedTemplates() async {
    try {
      final templates = await _service.listSavedTemplates(
        organizationId: _draft.organizationId,
      );
      if (mounted) setState(() => _savedTemplates = templates);
    } catch (_) {
      // Curated templates remain available when saved templates are offline.
    }
  }

  void _applySavedTemplate(Map<String, dynamic> template) {
    final form = Map<String, dynamic>.from(
      template['formData'] as Map? ?? const {},
    );
    final replacement = EventWizardDraft.fromJson({'formData': form});
    replacement
      ..draftId = _draft.draftId
      ..revision = _draft.revision
      ..mode = _draft.mode
      ..sourceEventId = _draft.sourceEventId
      ..sourceSeriesId = _draft.sourceSeriesId
      ..sourceEventRevision = _draft.sourceEventRevision
      ..currentStage = _draft.currentStage
      ..startAt = _draft.startAt
      ..endAt = _draft.endAt
      ..organizationId = _draft.organizationId;
    _draft = replacement;
    _titleController.text = _draft.title;
    _descriptionController.text = _draft.description;
    _onlineLocationController.text = _draft.locationType == 'online'
        ? _draft.location
        : '';
    _capacityController.text = _draft.capacity?.toString() ?? '';
    _priceController.text = _draft.priceUsd > 0
        ? _draft.priceUsd.toStringAsFixed(2)
        : '';
    _refundController.text = _draft.refundTerms;
    _accessibilityController.text = _draft.accessibilityDetails;
    _thingsController.text = _draft.thingsToBring.join(', ');
    _contactNameController.text = _draft.publicContactName;
    _contactEmailController.text = _draft.publicContactEmail;
    setState(() {});
    _scheduleAutosave();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_saveNow());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autosaveTimer?.cancel();
    _titleFocus.dispose();
    _locationFocus.dispose();
    _scrollController.dispose();
    for (final controller in [
      _titleController,
      _descriptionController,
      _onlineLocationController,
      _capacityController,
      _priceController,
      _refundController,
      _accessibilityController,
      _thingsController,
      _contactNameController,
      _contactEmailController,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _syncControllersToDraft() {
    _draft.title = _titleController.text;
    _draft.description = _descriptionController.text;
    if (_draft.locationType == 'online') {
      _draft.location = _onlineLocationController.text;
      _draft.locationName = _onlineLocationController.text;
    }
    _draft.capacity = _capacityController.text.trim().isEmpty
        ? null
        : int.tryParse(_capacityController.text.trim());
    _draft.priceUsd = double.tryParse(_priceController.text.trim()) ?? 0;
    _draft.refundTerms = _refundController.text;
    _draft.accessibilityDetails = _accessibilityController.text;
    _draft.thingsToBring = _thingsController.text
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    _draft.publicContactName = _contactNameController.text;
    _draft.publicContactEmail = _contactEmailController.text;
  }

  void _onFieldChanged() {
    _syncControllersToDraft();
    _scheduleAutosave();
    if (mounted) setState(() {});
  }

  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 800), _saveNow);
  }

  Future<void> _saveNow() async {
    _autosaveTimer?.cancel();
    _syncControllersToDraft();
    if (!mounted) return;
    setState(() => _saveState = EventWizardSaveState.saving);
    try {
      await _service.saveDraft(_draft);
      unawaited(
        _funnel.record(
          'event_wizard_draft_saved',
          dimensions: {
            'stage': _draft.currentStage.name,
            'mode': _draft.mode,
            'saveState': 'server',
          },
        ),
      );
      if (mounted) setState(() => _saveState = EventWizardSaveState.saved);
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'aborted') {
        final conflict = EventWizardDraft.fromJson({
          'mode': _draft.mode,
          'sourceEventId': _draft.sourceEventId,
          'sourceSeriesId': _draft.sourceSeriesId,
          'sourceEventRevision': _draft.sourceEventRevision,
          'currentStage': _draft.currentStage.index,
          'formData': _draft.toFormJson(),
        });
        _draft = conflict;
        await _service.saveLocalDraft(_draft);
        if (!mounted) return;
        setState(() => _saveState = EventWizardSaveState.savedOnDevice);
        _showError(
          'This draft changed on another device. Your work was preserved as a conflict copy.',
        );
        return;
      }
      await _service.saveLocalDraft(_draft);
      if (!mounted) return;
      setState(() {
        _saveState = error.code == 'unavailable'
            ? EventWizardSaveState.offline
            : EventWizardSaveState.savedOnDevice;
      });
    } catch (_) {
      await _service.saveLocalDraft(_draft);
      if (mounted) {
        setState(() => _saveState = EventWizardSaveState.savedOnDevice);
      }
    }
  }

  String get _saveLabel => switch (_saveState) {
    EventWizardSaveState.saving => 'Saving…',
    EventWizardSaveState.saved => 'Saved',
    EventWizardSaveState.savedOnDevice => 'Saved on this device',
    EventWizardSaveState.offline => 'Offline — saved on this device',
    EventWizardSaveState.failed => 'Couldn’t sync',
    _ => 'Autosave on',
  };

  IconData get _saveIcon => switch (_saveState) {
    EventWizardSaveState.saving => Icons.sync,
    EventWizardSaveState.saved => Icons.cloud_done_outlined,
    EventWizardSaveState.offline => Icons.cloud_off_outlined,
    EventWizardSaveState.failed => Icons.error_outline,
    _ => Icons.save_outlined,
  };

  bool _validateStage() {
    _syncControllersToDraft();
    if (_draft.currentStage == EventWizardStage.basics) {
      if (_draft.title.trim().isEmpty) {
        _titleFocus.requestFocus();
        _showError('Add an event title to continue.');
        return false;
      }
      if (!_draft.endAt.isAfter(_draft.startAt)) {
        _showError('The event must end after it starts.');
        return false;
      }
      final validLocation = _draft.locationType == 'online'
          ? _draft.location.trim().isNotEmpty
          : _draft.location.trim().isNotEmpty &&
                !(_draft.latitude == 0 && _draft.longitude == 0);
      if (!validLocation) {
        _locationFocus.requestFocus();
        _showError('Add a valid event location to continue.');
        return false;
      }
    }
    if (_draft.currentStage == EventWizardStage.registration) {
      if (_draft.capacity != null && _draft.capacity! <= 0) {
        _showError('Capacity must be a positive whole number.');
        return false;
      }
      if (_draft.registrationMode == EventRegistrationMode.paidTicket) {
        _showError(
          'Paid ticket setup remains unavailable until secure checkout is enabled.',
        );
        return false;
      }
      for (final question in _draft.questions) {
        if (question.prompt.trim().isEmpty) {
          _showError('Every attendee question needs a prompt.');
          return false;
        }
        if ((question.type == EventQuestionType.singleChoice ||
                question.type == EventQuestionType.multipleChoice) &&
            question.options.where((value) => value.trim().isNotEmpty).length <
                2) {
          _showError('Choice questions need at least two options.');
          return false;
        }
      }
    }
    if (_draft.currentStage == EventWizardStage.publish &&
        !_draft.isPrivate &&
        _draft.primaryDiscoveryCategoryId == null) {
      _showError('Choose a primary discovery category before publishing.');
      return false;
    }
    return _formKey.currentState?.validate() ?? true;
  }

  void _showError(String message) {
    unawaited(
      _funnel.record(
        'event_wizard_stage_error',
        dimensions: {'stage': _draft.currentStage.name, 'mode': _draft.mode},
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _continue() async {
    if (!_validateStage()) return;
    await _saveNow();
    if (!mounted) return;
    if (_draft.currentStage == EventWizardStage.publish) {
      await _publish();
      return;
    }
    unawaited(
      _funnel.record(
        'event_wizard_stage_completed',
        dimensions: {'stage': _draft.currentStage.name, 'mode': _draft.mode},
      ),
    );
    setState(() {
      _draft.currentStage =
          EventWizardStage.values[_draft.currentStage.index + 1];
    });
    _recordStageView();
    _scrollController.jumpTo(0);
    _scheduleAutosave();
  }

  Future<void> _back() async {
    if (_draft.currentStage == EventWizardStage.basics) {
      await _close();
      return;
    }
    await _saveNow();
    if (!mounted) return;
    setState(() {
      _draft.currentStage =
          EventWizardStage.values[_draft.currentStage.index - 1];
    });
    _recordStageView();
    _scrollController.jumpTo(0);
  }

  Future<void> _close() async {
    await _saveNow();
    unawaited(
      _funnel.record(
        'event_wizard_abandoned',
        dimensions: {'stage': _draft.currentStage.name, 'mode': _draft.mode},
      ),
    );
    if (mounted) Navigator.maybePop(context);
  }

  Future<void> _publish() async {
    final recurrenceScope = await _chooseRecurrenceScope();
    if (recurrenceScope == null) return;
    setState(() => _publishing = true);
    unawaited(
      _funnel.record(
        'event_wizard_publish_attempted',
        dimensions: {
          'mode': _draft.mode,
          'organizationContext': _draft.organizationId == null
              ? 'personal'
              : 'group',
        },
      ),
    );
    try {
      final result = await _service.publish(
        _draft,
        recurrenceScope: recurrenceScope,
      );
      unawaited(
        _funnel.record(
          'event_wizard_publish_succeeded',
          dimensions: {'mode': _draft.mode, 'result': result.status},
        ),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.celebration_outlined, size: 44),
          title: Text(
            result.status == 'pending_approval'
                ? 'Submitted for approval'
                : 'Your event is live',
          ),
          content: Text(
            result.eventIds.length > 1
                ? '${result.eventIds.length} recurring occurrences were created.'
                : 'The attendee page and sharing link are ready.',
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context, result.eventId);
              },
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } on FirebaseFunctionsException catch (error) {
      unawaited(
        _funnel.record(
          'event_wizard_publish_failed',
          dimensions: {'mode': _draft.mode, 'errorCategory': error.code},
        ),
      );
      if (!mounted) return;
      final details = error.details is Map
          ? Map<String, dynamic>.from(error.details as Map)
          : const <String, dynamic>{};
      final fieldErrors = details['errors'] as List?;
      _showError(
        fieldErrors?.isNotEmpty == true
            ? Map<String, dynamic>.from(
                    fieldErrors!.first as Map,
                  )['message']?.toString() ??
                  error.message ??
                  'Could not publish the event.'
            : error.message ?? 'Could not publish the event.',
      );
    } catch (_) {
      if (mounted) {
        _showError('Could not publish the event. Your draft is safe.');
      }
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<String?> _chooseRecurrenceScope() async {
    if (_draft.mode != 'edit' || _draft.sourceSeriesId == null) {
      return 'this_occurrence';
    }
    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Apply changes to'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'this_occurrence'),
            child: const ListTile(
              leading: Icon(Icons.event_outlined),
              title: Text('This occurrence'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'this_and_future'),
            child: const ListTile(
              leading: Icon(Icons.event_repeat_outlined),
              title: Text('This and future occurrences'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'entire_series'),
            child: const ListTile(
              leading: Icon(Icons.calendar_month_outlined),
              title: Text('Entire series'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1800,
      imageQuality: 88,
    );
    if (image == null) return;
    final bytes = await image.readAsBytes();
    setState(() => _pendingImage = bytes);
    try {
      final url = await _service.uploadDraftImage(draft: _draft, bytes: bytes);
      if (!mounted) return;
      setState(() => _draft.imageUrl = url);
      _scheduleAutosave();
    } catch (_) {
      if (mounted) {
        _showError(
          'The image is saved locally and will upload when you retry.',
        );
      }
    }
  }

  Future<void> _pickLocation() async {
    final result = await Navigator.push<LocationPickerResult>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          initialLocation: _draft.latitude == 0 && _draft.longitude == 0
              ? null
              : LatLng(_draft.latitude, _draft.longitude),
          initialRadius: _draft.radius,
          initialPlaceId: _draft.placeId,
          initialDisplayName: _draft.locationName,
          initialAddress: _draft.location,
          initialCity: _draft.city,
          initialRegionCode: _draft.regionCode,
          initialCountryCode: _draft.countryCode,
          initialStreetAddress: _draft.streetAddress,
          initialPostalCode: _draft.postalCode,
          initialEventTimeZone: _draft.eventTimeZone,
        ),
      ),
    );
    if (result == null) return;
    setState(() {
      _draft.latitude = result.location.latitude;
      _draft.longitude = result.location.longitude;
      _draft.radius = result.radius;
      _draft.placeId = result.placeId ?? '';
      _draft.locationName = result.displayName;
      _draft.location = result.formattedAddress;
      _draft.city = result.city;
      _draft.regionCode = result.regionCode;
      _draft.countryCode = result.countryCode;
      _draft.streetAddress = result.streetAddress;
      _draft.postalCode = result.postalCode;
      _draft.eventTimeZone = result.eventTimeZone;
    });
    _scheduleAutosave();
  }

  Future<void> _pickDateTime(bool start) async {
    final current = start ? _draft.startAt : _draft.endAt;
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 366)),
      helpText: start ? 'Choose event date' : 'Choose end date',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
      helpText: start ? 'Choose start time' : 'Choose end time',
    );
    if (time == null) return;
    final selected = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      if (start) {
        final duration = _draft.endAt.difference(_draft.startAt);
        _draft.startAt = selected;
        _draft.endAt = selected.add(
          duration.isNegative ? const Duration(hours: 1) : duration,
        );
      } else {
        _draft.endAt = selected;
      }
    });
    _scheduleAutosave();
  }

  Future<void> _showDrafts() async {
    setState(() => _loadingDrafts = true);
    try {
      _availableDrafts = await _service.listDrafts();
    } catch (_) {
      final local = await _service.restoreLocalDraft();
      _availableDrafts = local == null ? const [] : [local];
    }
    if (!mounted) return;
    setState(() => _loadingDrafts = false);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .68,
          child: Column(
            children: [
              const ListTile(
                title: Text(
                  'Your drafts',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text('Resume where you left off on any device.'),
              ),
              Expanded(
                child: _availableDrafts.isEmpty
                    ? const Center(child: Text('No saved drafts yet.'))
                    : ListView.builder(
                        itemCount: _availableDrafts.length,
                        itemBuilder: (context, index) {
                          final draft = _availableDrafts[index];
                          return ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.edit_note),
                            ),
                            title: Text(
                              draft.title.isEmpty
                                  ? 'Untitled event'
                                  : draft.title,
                            ),
                            subtitle: Text(
                              'Step ${draft.currentStage.index + 1} of 4',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.pop(context);
                              setState(() {
                                _draft = draft;
                                _replaceControllersFromDraft();
                              });
                              unawaited(
                                _funnel.record(
                                  'event_wizard_draft_restored',
                                  dimensions: {
                                    'stage': draft.currentStage.name,
                                    'mode': draft.mode,
                                  },
                                ),
                              );
                              _recordStageView();
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _replaceControllersFromDraft() {
    _titleController.text = _draft.title;
    _descriptionController.text = _draft.description;
    _onlineLocationController.text = _draft.locationType == 'online'
        ? _draft.location
        : '';
    _capacityController.text = _draft.capacity?.toString() ?? '';
    _priceController.text = _draft.priceUsd > 0
        ? _draft.priceUsd.toStringAsFixed(2)
        : '';
    _refundController.text = _draft.refundTerms;
    _accessibilityController.text = _draft.accessibilityDetails;
    _thingsController.text = _draft.thingsToBring.join(', ');
    _contactNameController.text = _draft.publicContactName;
    _contactEmailController.text = _draft.publicContactEmail;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final desktop = width >= 1050;
    final showPreview = desktop && _showPreview;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_close());
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F8FC),
        appBar: _buildAppBar(desktop),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              if (!desktop) _MobileProgress(stage: _draft.currentStage),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (desktop)
                      SizedBox(
                        width: 245,
                        child: _StageRail(
                          stage: _draft.currentStage,
                          onSelected: _jumpToStage,
                        ),
                      ),
                    Expanded(
                      child: Form(
                        key: _formKey,
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          padding: EdgeInsets.fromLTRB(
                            desktop ? 32 : 18,
                            28,
                            desktop ? 32 : 18,
                            120,
                          ),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 760),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 180),
                                child: KeyedSubtree(
                                  key: ValueKey(_draft.currentStage),
                                  child: _buildStage(),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (showPreview)
                      Container(
                        width: 370,
                        padding: const EdgeInsets.fromLTRB(8, 28, 28, 120),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Live attendee preview',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 10),
                            Expanded(child: _AttendeePreview(draft: _draft)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              _buildFooter(desktop),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(bool desktop) => AppBar(
    automaticallyImplyLeading: false,
    backgroundColor: Theme.of(context).colorScheme.surface,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    title: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _draft.mode == 'edit' ? 'Edit event' : 'Create event',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        Semantics(
          liveRegion: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_saveIcon, size: 14),
              const SizedBox(width: 5),
              Text(_saveLabel, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      ],
    ),
    actions: [
      TextButton.icon(
        onPressed: _loadingDrafts ? null : _showDrafts,
        icon: _loadingDrafts
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.folder_open_outlined),
        label: Text(desktop ? 'Drafts' : ''),
      ),
      IconButton(
        tooltip: desktop && _showPreview
            ? 'Hide preview'
            : 'Preview attendee page',
        onPressed: desktop
            ? () => setState(() => _showPreview = !_showPreview)
            : _openPreview,
        icon: const Icon(Icons.preview_outlined),
      ),
      IconButton(
        tooltip: 'Save and close',
        onPressed: _close,
        icon: const Icon(Icons.close),
      ),
      const SizedBox(width: 8),
    ],
  );

  void _jumpToStage(EventWizardStage stage) {
    if (stage.index > _draft.currentStage.index && !_validateStage()) return;
    setState(() => _draft.currentStage = stage);
    _scrollController.jumpTo(0);
    _scheduleAutosave();
  }

  Widget _buildStage() => switch (_draft.currentStage) {
    EventWizardStage.basics => _buildBasics(),
    EventWizardStage.registration => _buildRegistration(),
    EventWizardStage.experience => _buildExperience(),
    EventWizardStage.publish => _buildPublish(),
  };

  Widget _stageHeading(String eyebrow, String title, String description) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              eyebrow.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );

  Widget _card({required Widget child}) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 1,
      shadowColor: const Color(0x18000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: const EdgeInsets.all(20), child: child),
    ),
  );

  Widget _buildBasics() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _stageHeading(
        'Step 1 of 4',
        'Start with the essentials',
        'Give attendees a clear reason to show up. You can refine operations later.',
      ),
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle(
              icon: Icons.account_circle_outlined,
              title: 'Hosting as',
              subtitle: 'Choose the identity attendees will see.',
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String?>(
              isExpanded: true,
              initialValue: _draft.organizationId,
              decoration: const InputDecoration(labelText: 'Host'),
              items: [
                if (!widget.forceOrganizationEvent)
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Personal profile'),
                  ),
                if (_draft.organizationId != null &&
                    !_organizations.any(
                      (organization) =>
                          organization['id'] == _draft.organizationId,
                    ))
                  DropdownMenuItem<String?>(
                    value: _draft.organizationId,
                    child: const Text('Selected group'),
                  ),
                ..._organizations.map(
                  (organization) => DropdownMenuItem<String?>(
                    value: organization['id'],
                    child: Text(organization['name'] ?? 'Group'),
                  ),
                ),
              ],
              onChanged: widget.forceOrganizationEvent
                  ? null
                  : (value) {
                      setState(() {
                        _draft.organizationId = value;
                        if (value != null) _draft.isPrivate = true;
                      });
                      _scheduleAutosave();
                      unawaited(_loadSavedTemplates());
                    },
            ),
          ],
        ),
      ),
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle(
              icon: Icons.auto_awesome_outlined,
              title: 'Start with a template',
              subtitle: 'Templates set useful defaults without locking you in.',
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: EventWizardTemplate.curated.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, index) {
                  final template = EventWizardTemplate.curated[index];
                  return _TemplateTile(
                    template: template,
                    selected:
                        _draft.primaryDiscoveryCategoryId ==
                            template.categoryId &&
                        _draft.registrationMode == template.registrationMode,
                    onTap: () {
                      setState(() => _draft.applyTemplate(template));
                      unawaited(
                        _funnel.record(
                          'event_wizard_template_selected',
                          dimensions: {
                            'templateId': template.id,
                            'mode': _draft.mode,
                          },
                        ),
                      );
                      _scheduleAutosave();
                    },
                  );
                },
              ),
            ),
            if (_savedTemplates.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(
                'Your saved templates',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _savedTemplates
                    .map(
                      (template) => ActionChip(
                        avatar: const Icon(Icons.bookmark_outline, size: 18),
                        label: Text(template['name']?.toString() ?? 'Template'),
                        onPressed: () => _applySavedTemplate(template),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle(icon: Icons.edit_note, title: 'Event details'),
            const SizedBox(height: 18),
            TextFormField(
              controller: _titleController,
              focusNode: _titleFocus,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 160,
              decoration: const InputDecoration(
                labelText: 'Event title',
                hintText: 'Community breakfast',
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _descriptionController,
              textCapitalization: TextCapitalization.sentences,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'What will attendees experience?',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 18),
            _CoverPicker(
              bytes: _pendingImage,
              imageUrl: _draft.imageUrl,
              onTap: _pickImage,
            ),
          ],
        ),
      ),
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle(
              icon: Icons.schedule_outlined,
              title: 'Date and time',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _DateTimeTile(
                    label: 'Starts',
                    value: _draft.startAt,
                    onTap: () => _pickDateTime(true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DateTimeTile(
                    label: 'Ends',
                    value: _draft.endAt,
                    onTap: () => _pickDateTime(false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Timezone: ${_draft.eventTimeZone}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Divider(height: 32),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _draft.recurrenceEnabled,
              title: const Text(
                'Repeat this event',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'Each occurrence has its own capacity, registration, and attendance.',
              ),
              onChanged: (value) {
                setState(() => _draft.recurrenceEnabled = value);
                if (value) {
                  unawaited(
                    _funnel.record(
                      'event_wizard_recurrence_configured',
                      dimensions: {'mode': _draft.mode},
                    ),
                  );
                }
                _scheduleAutosave();
              },
            ),
            if (_draft.recurrenceEnabled) _buildRecurrence(),
          ],
        ),
      ),
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle(
              icon: Icons.place_outlined,
              title: 'Format and location',
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'in_person',
                  label: Text('In person'),
                  icon: Icon(Icons.place_outlined),
                ),
                ButtonSegment(
                  value: 'online',
                  label: Text('Online'),
                  icon: Icon(Icons.videocam_outlined),
                ),
              ],
              selected: {_draft.locationType},
              showSelectedIcon: false,
              onSelectionChanged: (value) {
                setState(() {
                  _draft.locationType = value.first;
                  if (value.first == 'online') {
                    _draft.location = _onlineLocationController.text;
                    _draft.latitude = 0;
                    _draft.longitude = 0;
                  }
                });
                _scheduleAutosave();
              },
            ),
            const SizedBox(height: 16),
            if (_draft.locationType == 'online')
              TextFormField(
                controller: _onlineLocationController,
                focusNode: _locationFocus,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Online location or meeting link',
                  hintText: 'Zoom, Teams, or another secure meeting location',
                ),
              )
            else
              Semantics(
                button: true,
                label: _draft.location.isEmpty
                    ? 'Select event location'
                    : 'Change event location',
                child: ListTile(
                  focusNode: _locationFocus,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: const CircleAvatar(
                    child: Icon(Icons.location_on_outlined),
                  ),
                  title: Text(
                    _draft.locationName.isEmpty
                        ? 'Select a venue or address'
                        : _draft.locationName,
                  ),
                  subtitle: _draft.location.isEmpty
                      ? null
                      : Text(_draft.location),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickLocation,
                ),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _buildRecurrence() => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      children: [
        DropdownButtonFormField<EventRecurrenceFrequency>(
          initialValue: _draft.recurrenceFrequency,
          decoration: const InputDecoration(labelText: 'Repeats'),
          items: const [
            DropdownMenuItem(
              value: EventRecurrenceFrequency.daily,
              child: Text('Daily'),
            ),
            DropdownMenuItem(
              value: EventRecurrenceFrequency.weekly,
              child: Text('Weekly'),
            ),
            DropdownMenuItem(
              value: EventRecurrenceFrequency.weekdays,
              child: Text('Selected weekdays'),
            ),
            DropdownMenuItem(
              value: EventRecurrenceFrequency.monthly,
              child: Text('Monthly'),
            ),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => _draft.recurrenceFrequency = value);
            _scheduleAutosave();
          },
        ),
        if (_draft.recurrenceFrequency ==
            EventRecurrenceFrequency.weekdays) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (var day = 1; day <= 7; day++)
                FilterChip(
                  label: Text(
                    const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][day - 1],
                  ),
                  selected: _draft.recurrenceWeekDays.contains(day),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _draft.recurrenceWeekDays = [
                          ..._draft.recurrenceWeekDays,
                          day,
                        ]..sort();
                      } else {
                        _draft.recurrenceWeekDays = _draft.recurrenceWeekDays
                            .where((v) => v != day)
                            .toList();
                      }
                    });
                    _scheduleAutosave();
                  },
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'count', label: Text('Occurrence count')),
            ButtonSegment(value: 'date', label: Text('End date')),
          ],
          selected: {_draft.recurrenceEndMode},
          onSelectionChanged: (value) {
            setState(() => _draft.recurrenceEndMode = value.first);
            _scheduleAutosave();
          },
        ),
        const SizedBox(height: 12),
        if (_draft.recurrenceEndMode == 'count')
          DropdownButtonFormField<int>(
            initialValue:
                [
                  2,
                  3,
                  4,
                  5,
                  6,
                  8,
                  10,
                  12,
                  26,
                  52,
                ].contains(_draft.recurrenceCount)
                ? _draft.recurrenceCount
                : 2,
            decoration: const InputDecoration(
              labelText: 'Number of occurrences',
              helperText: 'Free 12 · Basic 26 · Premium 52 per rolling year.',
            ),
            items: [
              for (final count in [2, 3, 4, 5, 6, 8, 10, 12, 26, 52])
                DropdownMenuItem(
                  value: count,
                  child: Text('$count occurrences'),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _draft.recurrenceCount = value);
              _scheduleAutosave();
            },
          )
        else
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_busy_outlined),
            title: const Text('Series ends'),
            subtitle: Text(
              DateFormat.yMMMd().format(
                _draft.recurrenceEndDate ??
                    _draft.startAt.add(const Duration(days: 30)),
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickRecurrenceEndDate,
          ),
      ],
    ),
  );

  Future<void> _pickRecurrenceEndDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate:
          _draft.recurrenceEndDate ??
          _draft.startAt.add(const Duration(days: 30)),
      firstDate: _draft.startAt.add(const Duration(days: 1)),
      lastDate: _draft.startAt.add(const Duration(days: 365)),
    );
    if (date == null) return;
    setState(() => _draft.recurrenceEndDate = date);
    _scheduleAutosave();
  }

  Widget _buildRegistration() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _stageHeading(
        'Step 2 of 4',
        'Shape registration',
        'Choose how people reserve a place, then ask only what you truly need.',
      ),
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle(
              icon: Icons.how_to_reg_outlined,
              title: 'Registration type',
            ),
            const SizedBox(height: 16),
            RadioGroup<EventRegistrationMode>(
              groupValue: _draft.registrationMode,
              onChanged: (value) {
                if (value == null ||
                    value == EventRegistrationMode.paidTicket) {
                  return;
                }
                setState(() {
                  _draft.registrationMode = value;
                  final eligibility = value == EventRegistrationMode.rsvp
                      ? CheckInEligibility.open
                      : CheckInEligibility.registeredOnly;
                  _draft.checkInPolicy = _draft.checkInPolicy.copyWith(
                    eligibility: eligibility,
                  );
                });
                _scheduleAutosave();
              },
              child: Column(
                children: EventRegistrationMode.values.map((mode) {
                  final paid = mode == EventRegistrationMode.paidTicket;
                  final title = switch (mode) {
                    EventRegistrationMode.rsvp => 'RSVP',
                    EventRegistrationMode.freeTicket => 'Free ticket',
                    EventRegistrationMode.paidTicket => 'Paid ticket',
                  };
                  final subtitle = switch (mode) {
                    EventRegistrationMode.rsvp =>
                      'A simple attendee list without ticket scanning.',
                    EventRegistrationMode.freeTicket =>
                      'Issue a QR ticket for each confirmed attendee.',
                    EventRegistrationMode.paidTicket =>
                      'Available after secure paid checkout is enabled.',
                  };
                  return RadioListTile<EventRegistrationMode>(
                    value: mode,
                    enabled: !paid,
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (paid) ...[
                          const SizedBox(width: 8),
                          const Chip(
                            label: Text('Unavailable'),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ],
                    ),
                    subtitle: Text(subtitle),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle(
              icon: Icons.people_outline,
              title: 'Capacity and approval',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _capacityController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Capacity (optional)',
                hintText: 'Unlimited',
                helperText: 'Leave blank when there is no attendance limit.',
              ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<EventApprovalMode>(
              segments: const [
                ButtonSegment(
                  value: EventApprovalMode.automatic,
                  label: Text('Automatic'),
                ),
                ButtonSegment(
                  value: EventApprovalMode.manual,
                  label: Text('Organizer approval'),
                ),
              ],
              selected: {_draft.approvalMode},
              showSelectedIcon: false,
              onSelectionChanged: (value) {
                setState(() => _draft.approvalMode = value.first);
                _scheduleAutosave();
              },
            ),
            if (_draft.capacity != null)
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _draft.waitlistEnabled,
                title: const Text('Use a waitlist'),
                subtitle: const Text(
                  'Keep accepting interest after confirmed capacity is reached.',
                ),
                onChanged: (value) {
                  setState(() => _draft.waitlistEnabled = value);
                  _scheduleAutosave();
                },
              ),
          ],
        ),
      ),
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(
              icon: Icons.question_answer_outlined,
              title: 'Attendee questions',
              subtitle:
                  'Choose whether each answer is collected during registration or at check-in.',
              trailing: TextButton.icon(
                onPressed: _addQuestion,
                icon: const Icon(Icons.add),
                label: const Text('Add question'),
              ),
            ),
            if (_draft.questions.isEmpty)
              const _EmptyMiniState(
                icon: Icons.chat_bubble_outline,
                text: 'No extra questions. This keeps registration fast.',
              )
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _draft.questions.length,
                onReorderItem: (oldIndex, newIndex) {
                  setState(() {
                    final item = _draft.questions.removeAt(oldIndex);
                    _draft.questions.insert(newIndex, item);
                  });
                  _scheduleAutosave();
                },
                itemBuilder: (_, index) {
                  final question = _draft.questions[index];
                  return ListTile(
                    key: ValueKey(question.id),
                    leading: const Icon(Icons.drag_handle),
                    title: Text(question.prompt),
                    subtitle: Text(
                      '${_questionTypeLabel(question.type)} · '
                      '${question.timing == EventQuestionTiming.registration ? 'Registration' : 'Check-in'} · '
                      '${question.required ? 'Required' : 'Optional'}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Remove question',
                      onPressed: () {
                        setState(() => _draft.questions.removeAt(index));
                        _scheduleAutosave();
                      },
                      icon: const Icon(Icons.delete_outline),
                    ),
                    onTap: () => _editQuestion(question),
                  );
                },
              ),
          ],
        ),
      ),
    ],
  );

  String _questionTypeLabel(EventQuestionType type) => switch (type) {
    EventQuestionType.shortText => 'Short answer',
    EventQuestionType.longText => 'Long answer',
    EventQuestionType.singleChoice => 'Single choice',
    EventQuestionType.multipleChoice => 'Multiple choice',
    EventQuestionType.acknowledgement => 'Acknowledgement',
  };

  Future<void> _addQuestion() async {
    final question = EventWizardQuestion(
      id: 'question-${DateTime.now().microsecondsSinceEpoch}',
      prompt: '',
    );
    await _showQuestionEditor(question, isNew: true);
  }

  Future<void> _editQuestion(EventWizardQuestion question) =>
      _showQuestionEditor(question, isNew: false);

  Future<void> _showQuestionEditor(
    EventWizardQuestion question, {
    required bool isNew,
  }) async {
    final prompt = TextEditingController(text: question.prompt);
    final options = TextEditingController(text: question.options.join('\n'));
    var type = question.type;
    var timing = question.timing;
    var required = question.required;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            isNew ? 'Add attendee question' : 'Edit attendee question',
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: prompt,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Question'),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<EventQuestionType>(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: 'Answer type'),
                    items: [
                      for (final value in EventQuestionType.values)
                        DropdownMenuItem(
                          value: value,
                          child: Text(_questionTypeLabel(value)),
                        ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => type = value ?? type),
                  ),
                  if (type == EventQuestionType.singleChoice ||
                      type == EventQuestionType.multipleChoice) ...[
                    const SizedBox(height: 14),
                    TextField(
                      controller: options,
                      minLines: 2,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: 'Options',
                        helperText: 'Enter one option per line.',
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  SegmentedButton<EventQuestionTiming>(
                    segments: const [
                      ButtonSegment(
                        value: EventQuestionTiming.registration,
                        label: Text('Registration'),
                      ),
                      ButtonSegment(
                        value: EventQuestionTiming.checkIn,
                        label: Text('Check-in'),
                      ),
                    ],
                    selected: {timing},
                    onSelectionChanged: (value) =>
                        setDialogState(() => timing = value.first),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Required'),
                    value: required,
                    onChanged: (value) =>
                        setDialogState(() => required = value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save question'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && prompt.text.trim().isNotEmpty) {
      setState(() {
        question.prompt = prompt.text.trim();
        question.type = type;
        question.timing = timing;
        question.required = required;
        question.options = options.text
            .split('\n')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList();
        if (isNew) _draft.questions = [..._draft.questions, question];
      });
      _scheduleAutosave();
    }
    prompt.dispose();
    options.dispose();
  }

  Widget _buildExperience() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _stageHeading(
        'Step 3 of 4',
        'Design the day',
        'Set expectations, reduce uncertainty, and choose a smooth arrival experience.',
      ),
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(
              icon: Icons.view_timeline_outlined,
              title: 'Agenda',
              subtitle:
                  'Times stay relative to the start across recurring dates.',
              trailing: TextButton.icon(
                onPressed: _addAgendaItem,
                icon: const Icon(Icons.add),
                label: const Text('Add item'),
              ),
            ),
            if (_draft.agenda.isEmpty)
              const _EmptyMiniState(
                icon: Icons.schedule,
                text: 'Add an agenda when timing helps attendees prepare.',
              )
            else
              for (var index = 0; index < _draft.agenda.length; index++)
                ListTile(
                  leading: CircleAvatar(child: Text('${index + 1}')),
                  title: Text(_draft.agenda[index].title),
                  subtitle: Text(
                    '${_draft.agenda[index].offsetMinutes} minutes after the event starts',
                  ),
                  trailing: IconButton(
                    tooltip: 'Remove agenda item',
                    onPressed: () {
                      setState(() => _draft.agenda.removeAt(index));
                      _scheduleAutosave();
                    },
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
          ],
        ),
      ),
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle(
              icon: Icons.accessible_forward_outlined,
              title: 'Accessibility and preparation',
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in const [
                  'Wheelchair accessible',
                  'Accessible restroom',
                  'Captions',
                  'ASL interpretation',
                  'Low-sensory space',
                  'Service animals welcome',
                ])
                  FilterChip(
                    label: Text(option),
                    selected: _draft.accessibilityOptions.contains(option),
                    onSelected: (selected) {
                      setState(
                        () => _draft.accessibilityOptions = selected
                            ? [..._draft.accessibilityOptions, option]
                            : _draft.accessibilityOptions
                                  .where((value) => value != option)
                                  .toList(),
                      );
                      _scheduleAutosave();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _accessibilityController,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Accessibility details (optional)',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _thingsController,
              decoration: const InputDecoration(
                labelText: 'Things to bring',
                hintText: 'Photo ID, water bottle',
                helperText: 'Separate items with commas.',
              ),
            ),
          ],
        ),
      ),
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle(
              icon: Icons.support_agent_outlined,
              title: 'Public contact',
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _contactNameController,
                    decoration: const InputDecoration(
                      labelText: 'Contact name',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _contactEmailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Contact email',
                    ),
                  ),
                ),
              ],
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _draft.publicContactVisible,
              title: const Text('Show this contact on the attendee page'),
              onChanged: (value) {
                setState(() => _draft.publicContactVisible = value);
                _scheduleAutosave();
              },
            ),
          ],
        ),
      ),
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle(
              icon: Icons.admin_panel_settings_outlined,
              title: 'Event team',
              subtitle: 'Assign co-hosts and staff for this event.',
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.people_outline),
              title: const Text('Co-hosts'),
              subtitle: Text('${_draft.coHosts.length} assigned'),
              trailing: TextButton.icon(
                onPressed: () => _assignPerson(checkInStaff: false),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Add'),
              ),
            ),
            if (_draft.coHosts.isNotEmpty)
              Wrap(
                spacing: 8,
                children: _draft.coHosts
                    .map(
                      (uid) => InputChip(
                        label: Text(uid),
                        onDeleted: () {
                          setState(
                            () => _draft.coHosts = _draft.coHosts
                                .where((value) => value != uid)
                                .toList(),
                          );
                          _scheduleAutosave();
                        },
                      ),
                    )
                    .toList(),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.badge_outlined),
              title: const Text('Check-in staff'),
              subtitle: Text('${_draft.checkInStaff.length} assigned'),
              trailing: TextButton.icon(
                onPressed: () => _assignPerson(checkInStaff: true),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Add'),
              ),
            ),
            if (_draft.checkInStaff.isNotEmpty)
              Wrap(
                spacing: 8,
                children: _draft.checkInStaff
                    .map(
                      (uid) => InputChip(
                        label: Text(uid),
                        onDeleted: () {
                          setState(
                            () => _draft.checkInStaff = _draft.checkInStaff
                                .where((value) => value != uid)
                                .toList(),
                          );
                          _scheduleAutosave();
                        },
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle(
              icon: Icons.how_to_reg,
              title: 'Arrival and attendance',
              subtitle: 'Hybrid is the most flexible setup for most events.',
            ),
            const SizedBox(height: 14),
            for (final profile in CheckInProfile.values)
              _AttendancePresetTile(
                profile: profile,
                selected: _draft.checkInPolicy.profile == profile,
                onTap: () {
                  setState(
                    () => _draft.checkInPolicy = _draft.checkInPolicy.copyWith(
                      profile: profile,
                    ),
                  );
                  unawaited(
                    _funnel.record(
                      'event_wizard_attendance_preset_selected',
                      dimensions: {
                        'choice': profile.value,
                        'mode': _draft.mode,
                      },
                    ),
                  );
                  _scheduleAutosave();
                },
              ),
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              initiallyExpanded: _advancedAttendance,
              onExpansionChanged: (value) {
                setState(() => _advancedAttendance = value);
                if (value) {
                  unawaited(
                    _funnel.record(
                      'event_wizard_advanced_attendance_opened',
                      dimensions: {'mode': _draft.mode},
                    ),
                  );
                }
              },
              leading: const Icon(Icons.security_outlined),
              title: const Text(
                'Advanced check-in & security',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'Timing, re-entry, checkout, proximity, and pass protection',
              ),
              children: [_buildAdvancedAttendance()],
            ),
          ],
        ),
      ),
    ],
  );

  Future<void> _addAgendaItem() async {
    final title = TextEditingController();
    final offset = TextEditingController(text: '0');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add agenda item'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Agenda item'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: offset,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Minutes after event starts',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (saved == true && title.text.trim().isNotEmpty) {
      setState(
        () => _draft.agenda = [
          ..._draft.agenda,
          EventWizardAgendaItem(
            id: 'agenda-${DateTime.now().microsecondsSinceEpoch}',
            title: title.text.trim(),
            offsetMinutes: int.tryParse(offset.text) ?? 0,
          ),
        ],
      );
      _scheduleAutosave();
    }
    title.dispose();
    offset.dispose();
  }

  Future<void> _assignPerson({required bool checkInStaff}) async {
    final user = await showDialog<CustomerModel>(
      context: context,
      builder: (context) => _EventStaffPickerDialog(
        title: checkInStaff ? 'Add check-in staff' : 'Add co-host',
        excludedUids: {..._draft.coHosts, ..._draft.checkInStaff},
      ),
    );
    if (user == null) return;
    setState(() {
      if (checkInStaff) {
        _draft.checkInStaff = [..._draft.checkInStaff, user.uid];
      } else {
        _draft.coHosts = [..._draft.coHosts, user.uid];
      }
    });
    _scheduleAutosave();
  }

  Widget _buildAdvancedAttendance() => Column(
    children: [
      DropdownButtonFormField<CheckInEligibility>(
        initialValue: _draft.checkInPolicy.eligibility,
        decoration: const InputDecoration(labelText: 'Who may check in?'),
        items: const [
          DropdownMenuItem(
            value: CheckInEligibility.open,
            child: Text('Anyone — name entry allowed'),
          ),
          DropdownMenuItem(
            value: CheckInEligibility.registeredOnly,
            child: Text('Registered attendees only'),
          ),
          DropdownMenuItem(
            value: CheckInEligibility.ticketRequired,
            child: Text('Valid ticket required'),
          ),
        ],
        onChanged: (value) {
          if (value == null) return;
          setState(
            () => _draft.checkInPolicy = _draft.checkInPolicy.copyWith(
              eligibility: value,
            ),
          );
          _scheduleAutosave();
        },
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: _MinuteDropdown(
              label: 'Opens before',
              value: _draft.checkInPolicy.opensBeforeMinutes,
              onChanged: (value) => _setCheckInPolicy(
                _draft.checkInPolicy.copyWith(opensBeforeMinutes: value),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _MinuteDropdown(
              label: 'Closes after',
              value: _draft.checkInPolicy.closesAfterMinutes,
              onChanged: (value) => _setCheckInPolicy(
                _draft.checkInPolicy.copyWith(closesAfterMinutes: value),
              ),
            ),
          ),
        ],
      ),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        value: _draft.checkInPolicy.checkoutEnabled,
        title: const Text('Explicit checkout'),
        subtitle: const Text('No background tracking.'),
        onChanged: (value) => _setCheckInPolicy(
          _draft.checkInPolicy.copyWith(checkoutEnabled: value),
        ),
      ),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        value: _draft.checkInPolicy.allowReentry,
        title: const Text('Allow re-entry'),
        onChanged: (value) => _setCheckInPolicy(
          _draft.checkInPolicy.copyWith(allowReentry: value),
        ),
      ),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        value: _draft.checkInPolicy.staffFallback,
        title: const Text('Staff fallback'),
        onChanged: (value) => _setCheckInPolicy(
          _draft.checkInPolicy.copyWith(staffFallback: value),
        ),
      ),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        value: _draft.checkInPolicy.proximityAssist,
        title: const Text('One-time proximity assist'),
        subtitle: const Text(
          'Uses location only during check-in; never in the background.',
        ),
        onChanged: _draft.locationType == 'online'
            ? null
            : (value) => _setCheckInPolicy(
                _draft.checkInPolicy.copyWith(proximityAssist: value),
              ),
      ),
      if (_draft.checkInPolicy.staffEntryEnabled)
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _draft.checkInPolicy.passLockEnabled,
          title: const Text('Device Pass Lock'),
          subtitle: const Text(
            'Attendees unlock short-lived passes with device security.',
          ),
          onChanged: (value) => _setCheckInPolicy(
            _draft.checkInPolicy.copyWith(passLockEnabled: value),
          ),
        ),
      const ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.offline_bolt_outlined),
        title: Text('Offline-ready staff console'),
        subtitle: Text(
          'Eligible rosters and signed passes can be verified during connectivity loss.',
        ),
      ),
    ],
  );

  void _setCheckInPolicy(CheckInPolicy policy) {
    setState(() => _draft.checkInPolicy = policy);
    _scheduleAutosave();
  }

  Future<void> _saveAsTemplate() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save event template'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 100,
          decoration: const InputDecoration(labelText: 'Template name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    try {
      _syncControllersToDraft();
      await _service.saveTemplate(name: name, draft: _draft);
      await _loadSavedTemplates();
      if (mounted) {
        _showError('Template saved. Dates and attendee data were excluded.');
      }
    } catch (_) {
      if (mounted) {
        _showError('Could not save this template. Your event draft is safe.');
      }
    }
  }

  Widget _buildPublish() {
    final checks = _publicationChecks();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stageHeading(
          'Step 4 of 4',
          _draft.mode == 'edit' ? 'Review your changes' : 'Ready to publish?',
          'See the attendee experience, resolve anything missing, and publish with confidence.',
        ),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle(
                icon: Icons.visibility_outlined,
                title: 'Visibility and discovery',
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: !_draft.isPrivate,
                title: const Text(
                  'Public event',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  _draft.organizationId == null
                      ? 'Anyone can discover and share this event.'
                      : 'Public group events can appear in Discover.',
                ),
                onChanged: widget.forceOrganizationEvent
                    ? null
                    : (value) {
                        setState(() => _draft.isPrivate = !value);
                        _scheduleAutosave();
                      },
              ),
              if (!_draft.isPrivate) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _draft.primaryDiscoveryCategoryId,
                  decoration: const InputDecoration(
                    labelText: 'Primary discovery category',
                  ),
                  items: DiscoveryCategory.all
                      .map(
                        (category) => DropdownMenuItem(
                          value: category.id,
                          child: Row(
                            children: [
                              Icon(category.icon, size: 18),
                              const SizedBox(width: 8),
                              Text(category.label),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _draft.primaryDiscoveryCategoryId = value;
                      _draft.discoveryCategoryIds = value == null
                          ? []
                          : [value];
                    });
                    _scheduleAutosave();
                  },
                ),
              ],
            ],
          ),
        ),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle(
                icon: Icons.notifications_active_outlined,
                title: 'Attendee reminders',
                subtitle:
                    'Delivery respects attendee preferences and guest manage-page choices.',
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<EventReminderPreset>(
                initialValue: _draft.reminderPreset,
                decoration: const InputDecoration(
                  labelText: 'Reminder schedule',
                ),
                items: const [
                  DropdownMenuItem(
                    value: EventReminderPreset.off,
                    child: Text('Off'),
                  ),
                  DropdownMenuItem(
                    value: EventReminderPreset.dayBefore,
                    child: Text('24 hours before'),
                  ),
                  DropdownMenuItem(
                    value: EventReminderPreset.hourBefore,
                    child: Text('1 hour before'),
                  ),
                  DropdownMenuItem(
                    value: EventReminderPreset.dayAndHour,
                    child: Text('24 hours and 1 hour before — Recommended'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _draft.reminderPreset = value);
                  _scheduleAutosave();
                },
              ),
            ],
          ),
        ),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle(
                icon: Icons.fact_check_outlined,
                title: 'Publication checklist',
              ),
              const SizedBox(height: 10),
              for (final check in checks)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    check.complete ? Icons.check_circle : Icons.error_outline,
                    color: check.complete
                        ? Colors.green
                        : Theme.of(context).colorScheme.error,
                  ),
                  title: Text(check.label),
                  trailing: check.complete
                      ? null
                      : const Icon(Icons.chevron_right),
                  onTap: check.complete
                      ? null
                      : () => _jumpToStage(check.stage),
                ),
            ],
          ),
        ),
        if (MediaQuery.sizeOf(context).width < 1050)
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle(
                  icon: Icons.preview_outlined,
                  title: 'Attendee-page preview',
                ),
                const SizedBox(height: 16),
                _AttendeePreview(draft: _draft, compact: true),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _openPreview,
                  icon: const Icon(Icons.open_in_full),
                  label: const Text('Open full preview'),
                ),
              ],
            ),
          ),
        if (_draft.mode == 'edit')
          _card(
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionTitle(
                  icon: Icons.difference_outlined,
                  title: 'Changes ready to publish',
                ),
                SizedBox(height: 10),
                Text(
                  'Your live event remains unchanged until you publish. Date, location, privacy, capacity, and ticket changes trigger attendee update reconciliation.',
                ),
              ],
            ),
          ),
        _card(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.bookmark_add_outlined),
            title: const Text('Reuse this setup'),
            subtitle: const Text(
              'Save a sanitized template without dates, attendees, tickets, counters, or staff.',
            ),
            trailing: OutlinedButton(
              onPressed: _saveAsTemplate,
              child: const Text('Save template'),
            ),
          ),
        ),
      ],
    );
  }

  List<_PublishCheck> _publicationChecks() => [
    _PublishCheck(
      label: 'Title and attendee description',
      complete:
          _draft.title.trim().isNotEmpty &&
          _draft.description.trim().isNotEmpty,
      stage: EventWizardStage.basics,
    ),
    _PublishCheck(
      label: 'Valid date, time, and location',
      complete:
          _draft.endAt.isAfter(_draft.startAt) &&
          _draft.location.trim().isNotEmpty,
      stage: EventWizardStage.basics,
    ),
    _PublishCheck(
      label: 'Registration and capacity',
      complete: _draft.capacity == null || _draft.capacity! > 0,
      stage: EventWizardStage.registration,
    ),
    _PublishCheck(
      label: 'Arrival and attendance setup',
      complete: true,
      stage: EventWizardStage.experience,
    ),
    _PublishCheck(
      label: _draft.isPrivate
          ? 'Private visibility confirmed'
          : 'Discovery category selected',
      complete: _draft.isPrivate || _draft.primaryDiscoveryCategoryId != null,
      stage: EventWizardStage.publish,
    ),
  ];

  Future<void> _openPreview() {
    unawaited(
      _funnel.record(
        'event_wizard_preview_opened',
        dimensions: {'stage': _draft.currentStage.name, 'mode': _draft.mode},
      ),
    );
    return showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Attendee-page preview'),
            actions: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
                tooltip: 'Close preview',
              ),
            ],
          ),
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: _AttendeePreview(draft: _draft),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(bool desktop) => Container(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border(
        top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    ),
    padding: EdgeInsets.fromLTRB(
      desktop ? 28 : 16,
      12,
      desktop ? 28 : 16,
      12 + MediaQuery.paddingOf(context).bottom,
    ),
    child: Row(
      children: [
        Flexible(
          fit: FlexFit.loose,
          child: OutlinedButton.icon(
            onPressed: _publishing ? null : _back,
            icon: Icon(
              _draft.currentStage == EventWizardStage.basics
                  ? Icons.close
                  : Icons.arrow_back,
            ),
            label: Text(
              _draft.currentStage == EventWizardStage.basics
                  ? (desktop ? 'Save and exit' : 'Exit')
                  : 'Back',
            ),
          ),
        ),
        if (desktop) const Spacer() else const SizedBox(width: 12),
        if (desktop && _draft.currentStage != EventWizardStage.publish)
          Text(
            'Step ${_draft.currentStage.index + 1} of 4',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        if (desktop) const SizedBox(width: 18),
        Flexible(
          fit: FlexFit.loose,
          child: FilledButton.icon(
            onPressed: _publishing ? null : _continue,
            icon: _publishing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _draft.currentStage == EventWizardStage.publish
                        ? Icons.rocket_launch_outlined
                        : Icons.arrow_forward,
                  ),
            label: Text(
              _draft.currentStage == EventWizardStage.publish
                  ? (_draft.mode == 'edit'
                        ? 'Publish changes'
                        : 'Publish event')
                  : 'Continue',
            ),
          ),
        ),
      ],
    ),
  );
}

class _StageRail extends StatelessWidget {
  const _StageRail({required this.stage, required this.onSelected});
  final EventWizardStage stage;
  final ValueChanged<EventWizardStage> onSelected;

  @override
  Widget build(BuildContext context) => Container(
    color: Theme.of(context).colorScheme.surface,
    padding: const EdgeInsets.fromLTRB(18, 30, 18, 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'EVENT SETUP',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            letterSpacing: 1.2,
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        for (final value in EventWizardStage.values)
          _StageRailItem(
            stage: value,
            selected: value == stage,
            complete: value.index < stage.index,
            onTap: () => onSelected(value),
          ),
        const Spacer(),
        const Text(
          'Your changes autosave as a private draft.',
          style: TextStyle(fontSize: 12, color: Color(0xFF667085)),
        ),
      ],
    ),
  );
}

class _StageRailItem extends StatelessWidget {
  const _StageRailItem({
    required this.stage,
    required this.selected,
    required this.complete,
    required this.onTap,
  });
  final EventWizardStage stage;
  final bool selected;
  final bool complete;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = const [
      'Basics',
      'Registration',
      'Experience',
      'Publish',
    ][stage.index];
    final subtitle = const [
      'What and where',
      'Capacity and questions',
      'The day-of experience',
      'Review and share',
    ][stage.index];
    final primary = Theme.of(context).colorScheme.primary;
    return Semantics(
      selected: selected,
      label:
          'Step ${stage.index + 1} of 4, $title${complete ? ', complete' : ''}',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: selected ? primary.withValues(alpha: .09) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: selected || complete
                        ? primary
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    foregroundColor: selected || complete
                        ? Colors.white
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    child: complete
                        ? const Icon(Icons.check, size: 17)
                        : Text(
                            '${stage.index + 1}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: selected ? primary : null,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileProgress extends StatelessWidget {
  const _MobileProgress({required this.stage});
  final EventWizardStage stage;
  @override
  Widget build(BuildContext context) => Semantics(
    label:
        'Step ${stage.index + 1} of 4, ${const ['Basics', 'Registration', 'Experience', 'Publish'][stage.index]}',
    liveRegion: true,
    child: LinearProgressIndicator(value: (stage.index + 1) / 4, minHeight: 5),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(
          icon,
          size: 20,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            if (subtitle != null)
              Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      ?trailing,
    ],
  );
}

class _TemplateTile extends StatelessWidget {
  const _TemplateTile({
    required this.template,
    required this.selected,
    required this.onTap,
  });
  final EventWizardTemplate template;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 148,
    child: Material(
      color: selected
          ? Theme.of(context).colorScheme.primary.withValues(alpha: .1)
          : Theme.of(context).colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _templateIcon(template.iconName),
                color: Theme.of(context).colorScheme.primary,
              ),
              const Spacer(),
              Text(
                template.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

IconData _templateIcon(String value) => switch (value) {
  'handshake' => Icons.handshake_outlined,
  'school' => Icons.school_outlined,
  'podium' => Icons.campaign_outlined,
  'videocam' => Icons.videocam_outlined,
  'music' => Icons.music_note_outlined,
  'fitness' => Icons.fitness_center_outlined,
  'volunteer' => Icons.volunteer_activism_outlined,
  _ => Icons.groups_outlined,
};

class _EventStaffPickerDialog extends StatefulWidget {
  const _EventStaffPickerDialog({
    required this.title,
    required this.excludedUids,
  });

  final String title;
  final Set<String> excludedUids;

  @override
  State<_EventStaffPickerDialog> createState() =>
      _EventStaffPickerDialogState();
}

class _EventStaffPickerDialogState extends State<_EventStaffPickerDialog> {
  final _controller = TextEditingController();
  List<CustomerModel> _results = const [];
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.length < 2) return;
    setState(() => _loading = true);
    try {
      final users = await FirebaseFirestoreHelper().searchUsers(
        searchQuery: query,
        limit: 20,
      );
      if (!mounted) return;
      setState(() {
        _results = users
            .where((user) => !widget.excludedUids.contains(user.uid))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 480,
      height: 420,
      child: Column(
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              labelText: 'Search by name or username',
              suffixIcon: IconButton(
                tooltip: 'Search',
                onPressed: _search,
                icon: const Icon(Icons.search),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: _results.isEmpty
                ? const Center(child: Text('Search for an Attendus account.'))
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final user = _results[index];
                      return ListTile(
                        minTileHeight: 52,
                        leading: const CircleAvatar(
                          child: Icon(Icons.person_outline),
                        ),
                        title: Text(user.name),
                        subtitle: Text('@${user.username}'),
                        onTap: () => Navigator.pop(context, user),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
    ],
  );
}

class _DateTimeTile extends StatelessWidget {
  const _DateTimeTile({
    required this.label,
    required this.value,
    required this.onTap,
  });
  final String label;
  final DateTime value;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLowest,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 5),
            Text(
              DateFormat('MMM d, y').format(value),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            Text(DateFormat('h:mm a').format(value)),
          ],
        ),
      ),
    ),
  );
}

class _CoverPicker extends StatelessWidget {
  const _CoverPicker({
    required this.bytes,
    required this.imageUrl,
    required this.onTap,
  });
  final Uint8List? bytes;
  final String imageUrl;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: imageUrl.isEmpty && bytes == null
        ? 'Add event cover image'
        : 'Change event cover image',
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 220,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          image: bytes != null
              ? DecorationImage(image: MemoryImage(bytes!), fit: BoxFit.cover)
              : imageUrl.isNotEmpty
              ? DecorationImage(
                  image: NetworkImage(imageUrl),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: bytes == null && imageUrl.isEmpty
            ? const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate_outlined, size: 38),
                  SizedBox(height: 8),
                  Text(
                    'Add a cover image',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text('Recommended 3:2 ratio'),
                ],
              )
            : Align(
                alignment: Alignment.topRight,
                child: Container(
                  margin: const EdgeInsets.all(10),
                  padding: const EdgeInsets.all(9),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.edit, color: Colors.white, size: 18),
                ),
              ),
      ),
    ),
  );
}

class _AttendancePresetTile extends StatelessWidget {
  const _AttendancePresetTile({
    required this.profile,
    required this.selected,
    required this.onTap,
  });
  final CheckInProfile profile;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final (title, description, icon) = switch (profile) {
      CheckInProfile.selfCheckIn => (
        'Self check-in',
        'Guests use the rotating venue QR or short code.',
        Icons.qr_code_2,
      ),
      CheckInProfile.staffEntry => (
        'Staff-assisted',
        'Staff scan personal passes or use the eligible roster.',
        Icons.badge_outlined,
      ),
      CheckInProfile.hybrid => (
        'Hybrid — Recommended',
        'Both arrival paths stay available with staff fallback.',
        Icons.sync_alt,
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected
            ? Theme.of(context).colorScheme.primary.withValues(alpha: .08)
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        description,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MinuteDropdown extends StatelessWidget {
  const _MinuteDropdown({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) {
    const values = [0, 15, 30, 60, 90, 120, 180];
    return DropdownButtonFormField<int>(
      initialValue: values.contains(value) ? value : 60,
      decoration: InputDecoration(labelText: label),
      items: values
          .map(
            (minutes) => DropdownMenuItem(
              value: minutes,
              child: Text(minutes == 0 ? 'At event time' : '$minutes min'),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}

class _AttendeePreview extends StatelessWidget {
  const _AttendeePreview({required this.draft, this.compact = false});
  final EventWizardDraft draft;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final price = switch (draft.registrationMode) {
      EventRegistrationMode.rsvp => 'RSVP',
      EventRegistrationMode.freeTicket => 'Free',
      EventRegistrationMode.paidTicket =>
        'From \$${draft.priceUsd.toStringAsFixed(2)}',
    };
    return Semantics(
      label:
          'Attendee page preview for ${draft.title.isEmpty ? 'untitled event' : draft.title}',
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: 1,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 3 / 2,
              child: draft.imageUrl.isNotEmpty
                  ? Image.network(
                      draft.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _previewFallback(context),
                    )
                  : _previewFallback(context),
            ),
            Padding(
              padding: EdgeInsets.all(compact ? 16 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat(
                      'EEE, MMM d · h:mm a',
                    ).format(draft.startAt).toUpperCase(),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    draft.title.trim().isEmpty
                        ? 'Your event title'
                        : draft.title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _PreviewFact(
                    icon: draft.locationType == 'online'
                        ? Icons.videocam_outlined
                        : Icons.place_outlined,
                    text: draft.location.trim().isEmpty
                        ? 'Location will appear here'
                        : (draft.locationName.isEmpty
                              ? draft.location
                              : draft.locationName),
                  ),
                  _PreviewFact(
                    icon: Icons.confirmation_number_outlined,
                    text: price,
                  ),
                  if (draft.capacity != null)
                    _PreviewFact(
                      icon: Icons.people_outline,
                      text: '${draft.capacity} spots',
                    ),
                  if (draft.description.trim().isNotEmpty) ...[
                    const Divider(height: 28),
                    Text(
                      draft.description,
                      maxLines: compact ? 3 : 6,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: null,
                      child: Text(
                        draft.registrationMode == EventRegistrationMode.rsvp
                            ? 'RSVP'
                            : 'Get ticket',
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      'Preview only',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewFallback(BuildContext context) => Container(
    color: AttendUsTokens.blue.withValues(alpha: .1),
    child: Center(
      child: Icon(
        Icons.event_outlined,
        size: 58,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class _PreviewFact extends StatelessWidget {
  const _PreviewFact({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 7),
    child: Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      ],
    ),
  );
}

class _EmptyMiniState extends StatelessWidget {
  const _EmptyMiniState({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 14),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Icon(icon),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _PublishCheck {
  const _PublishCheck({
    required this.label,
    required this.complete,
    required this.stage,
  });
  final String label;
  final bool complete;
  final EventWizardStage stage;
}
