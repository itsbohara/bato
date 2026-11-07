"""Source-level guards for the launch Profile invariant.

Chrome opens Local State's last_used Profile and CEF's global request context follows it,
so the launch window must be pinned to Default and every page creation checked against the
absolute Profile directory. These tests read the client overlay; they do not launch anything.
"""
from pathlib import Path
import unittest

HERE = Path(__file__).parent
PATCH = (HERE / 'client.patch').read_text()
CLIENT = (HERE / 'client' / 'native_slot_client.mm').read_text()


class LaunchProfileTests(unittest.TestCase):
    def test_startup_pins_default_and_refuses_other_profile_directories(self):
        self.assertIn('+      pinned_strings.push_back("--profile-directory=Default");', PATCH)
        self.assertIn('--profile-directory is refused', PATCH)

    def test_startup_disables_omnibox_everywhere_whose_keep_alive_blocks_quit(self):
        self.assertIn('+      disabled_features += (disabled_features.empty() ? "" : ",") + std::string("OmniboxEverywhere");', PATCH)
        self.assertIn('keep-alive', PATCH)

    def test_launch_window_must_live_in_default_under_cache_root(self):
        self.assertIn('return launch ? root + "/Default" : root + "/" + key;', CLIENT)
        self.assertIn('anchor-context-path', CLIENT)
        self.assertIn('launch-context-not-default', CLIENT)

    def test_every_page_creation_checks_the_window_and_the_tab(self):
        self.assertIn('WindowMatchesProfile(token, *slot, profile_key, launch != 0)', CLIENT)
        self.assertIn('ContextPathIs(browser->GetHost()->GetRequestContext(), ExpectedProfilePath(profile_key, launch != 0))',
                      CLIENT)

    def test_other_profiles_are_direct_children_of_the_cache_root(self):
        self.assertNotIn('/profiles/', CLIENT)
        self.assertIn('root + "/" + key', CLIENT)


if __name__ == '__main__':
    unittest.main()
