import 'package:flclashx/models/clash_config.dart';
import 'package:flclashx/enum/enum.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Mihomo mips stack round-trips without changing the app default', () {
    final parsed = Tun.fromJson({'stack': 'mips'});
    expect(parsed.stack.name, 'mips');
    expect(parsed.toJson()['stack'], 'mips');
    expect(const Tun().stack, TunStack.mixed);
    expect(Tun.fromJson({'stack': 'gvisor'}).stack, TunStack.gvisor);
  });
}
