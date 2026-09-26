import 'package:beeamvo/services/update_check_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release links are restricted to the Beeamvo GitHub repository', () {
    expect(
      UpdateCheckService.isAllowedReleaseUrl(
        Uri.parse('https://github.com/justingorczyca/Beeamvo/releases/tag/v1'),
      ),
      isTrue,
    );
    expect(
      UpdateCheckService.isAllowedReleaseUrl(
        Uri.parse('https://evil.example/justingorczyca/Beeamvo/releases/v1'),
      ),
      isFalse,
    );
    expect(
      UpdateCheckService.isAllowedReleaseUrl(
        Uri.parse('https://github.com/other/repo/releases/v1'),
      ),
      isFalse,
    );
  });
}
