import 'package:flutter/material.dart';
import 'data.dart';
import 'ui.dart';

String _local(String p) => p.startsWith('233') ? '0${p.substring(3)}' : p;

class StaffScreen extends StatelessWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: Db.i,
      builder: (_, __) {
        final list = Db.i.all(Db.i.users)
          ..sort((a, b) => (a['role'] == 'admin' ? 0 : 1)
              .compareTo(b['role'] == 'admin' ? 0 : 1));
        return Scaffold(
            appBar: AppBar(title: const Text('Staff')),
            floatingActionButton: FloatingActionButton.extended(
                onPressed: () => _form(context),
                backgroundColor: sun,
                foregroundColor: ink,
                icon: const Icon(Icons.person_add),
                label: const Text('Add staff')),
            body: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                children: [
                  const Padding(
                      padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
                      child: Text(
                          'Staff can sell and add customers. They cannot see profit, expenses or reports.',
                          style: TextStyle(color: muted))),
                  for (final u in list)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Panel(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: ListTile(
                                leading: Avatar(u['name']),
                                title: Text(u['name'],
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(_local(u['phone']),
                                              style: figs(13,
                                                  w: FontWeight.w500,
                                                  c: muted)),
                                          const SizedBox(height: 6),
                                          u['role'] == 'admin'
                                              ? const Pill('Administrator',
                                                  bg: ink, fg: Colors.white)
                                              : u['active'] == false
                                                  ? const Pill('Access removed',
                                                      bg: badTint, fg: bad)
                                                  : const Pill('Staff',
                                                      bg: Color(0xFFDDF1E8),
                                                      fg: good),
                                        ])),
                                trailing: u['role'] == 'admin'
                                    ? null
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                            IconButton(
                                                icon:
                                                    const Icon(Icons.password),
                                                tooltip: 'Reset PIN',
                                                onPressed: () =>
                                                    _form(context, u)),
                                            Switch(
                                                value: u['active'] != false,
                                                activeThumbColor: good,
                                                onChanged: (v) => Db.i.put(
                                                    Db.i.users,
                                                    {...u, 'active': v})),
                                          ])))),
                  if (list.length == 1)
                    const Padding(
                        padding: EdgeInsets.only(top: 24),
                        child: Empty(Icons.badge_outlined, 'Just you so far',
                            'Add a staff member so they can sell from their own phone.')),
                ]));
      });

  void _form(BuildContext context, [Map? u]) {
    final n = TextEditingController(),
        ph = TextEditingController(),
        pin = TextEditingController();
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) => Padding(
            padding: EdgeInsets.fromLTRB(
                20, 4, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      u == null
                          ? 'Add staff member'
                          : 'New PIN for ${u['name']}',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                      u == null
                          ? 'They log in with this phone number and PIN.'
                          : 'Tell them the new PIN in person.',
                      style: const TextStyle(color: muted)),
                  const SizedBox(height: 16),
                  if (u == null) ...[
                    field(n, 'Name'),
                    field(ph, 'Phone number', num: true)
                  ],
                  field(pin, 'PIN (4 digits or more)', num: true, secret: true),
                  FilledButton(
                    onPressed: () async {
                      if (u != null) {
                        if (pin.text.length < 4) {
                          snack(ctx, 'PIN must be at least 4 digits.');
                          return;
                        }

                        await Db.i.resetPin(u, pin.text);
                      } else {
                        final err = await Db.i.addStaff(
                          n.text.trim(),
                          ph.text.trim(),
                          pin.text,
                        );

                        if (err != null) {
                          if (!ctx.mounted) return;
                          snack(ctx, err);
                          return;
                        }
                      }

                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                    },
                    child: Text(u == null ? 'Add staff' : 'Save new PIN'),
                  ),
                ])));
  }
}
