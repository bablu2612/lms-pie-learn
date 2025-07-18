# frozen_string_literal: true

#
# Copyright (C) 2015 - present Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.

require_relative "../../helpers/gradebook_common"
require_relative "../pages/gradebook_page"

# NOTE: We are aware that we're duplicating some unnecessary testcases, but this was the
# easiest way to review, and will be the easiest to remove after the feature flag is
# permanently removed. Testing both flag states is necessary during the transition phase.
shared_examples "Gradebook - total column menu options" do |ff_enabled|
  include_context "in-process server selenium tests"
  include GradebookCommon

  before :once do
    # Set feature flag state for the test run - this affects how the gradebook data is fetched, not the data setup
    if ff_enabled
      Account.site_admin.enable_feature!(:performance_improvements_for_gradebook)
    else
      Account.site_admin.disable_feature!(:performance_improvements_for_gradebook)
    end
    gradebook_data_setup
  end

  before { user_session(@teacher) }

  after { clear_local_storage }

  context "Display as" do
    before do
      Gradebook.visit(@course)
    end

    def should_show_percentages
      ff(".slick-row .slick-cell:nth-child(5)").each { |total| expect(total.text).to match(/%/) }
    end

    def should_show_points(*expected_points)
      ff(".slick-row .slick-cell:nth-child(5)").each do |total|
        raise Error "Total text is missing." unless total.text

        total.text.strip!
        expect(total.text).to include(expected_points.shift.to_s) unless total.text.empty?
      end
    end

    it "shows points when group weights are not set" do
      @course.show_total_grade_as_points = true
      @course.save!
      @course.reload
      Gradebook.visit(@course)

      should_show_points(15, 10, 10)
    end

    it "shows percentages when group weights are set", priority: "2" do
      @course.show_total_grade_as_points = false
      @course.save!
      @course.reload
      group = AssignmentGroup.where(name: @group.name).first
      group.group_weight = 50
      group.save!

      Gradebook.visit(@course)
      should_show_percentages
    end

    it "warns the teacher that studens will see a change" do
      Gradebook.visit(@course)
      Gradebook.open_display_dialog
      dialog = fj(".ui-dialog:visible")
      expect(dialog).to include_text("Warning")
    end

    it "allows toggling display by points or percent", priority: "1" do
      should_show_percentages
      Gradebook.toggle_grade_display

      wait_for_ajax_requests
      should_show_points(15, 10, 10)

      Gradebook.toggle_grade_display
      wait_for_ajax_requests
      should_show_percentages
    end

    it "changes the text on the toggle option when toggling" do
      dropdown_text = []

      Gradebook.select_total_column_option
      dropdown_text << f('[data-menu-item-id="grade-display-switcher"]').text

      Gradebook.select_total_column_option("grade-display-switcher", already_open: true)
      Gradebook.close_dialog_and_dont_show_again

      Gradebook.select_total_column_option
      dropdown_text << f('[data-menu-item-id="grade-display-switcher"]').text

      Gradebook.select_total_column_option("grade-display-switcher", already_open: true)

      Gradebook.select_total_column_option
      dropdown_text << f('[data-menu-item-id="grade-display-switcher"]').text

      expect(dropdown_text).to eq ["Display as Points", "Display as Percentage", "Display as Points"]
    end

    it "does not show the warning once dont show is checked" do
      Gradebook.open_display_dialog
      Gradebook.close_dialog_and_dont_show_again

      Gradebook.open_display_dialog
      expect(f("body")).not_to contain_jqcss(".ui-dialog:visible")
    end
  end

  context "Sort By" do
    before do
      Gradebook.visit(@course)
    end

    it "sort by > Low to High", priority: "1" do
      Gradebook.click_total_header_sort_by("Grade - Low to High")

      expect(final_score_for_row(0)).to eq @student_2_total_ignoring_ungraded
      expect(final_score_for_row(1)).to eq @student_3_total_ignoring_ungraded
      expect(final_score_for_row(2)).to eq @student_1_total_ignoring_ungraded
    end
  end

  context "Move to" do
    before do
      Gradebook.visit(@course)
    end

    it "Moves total column to the front", priority: "1" do
      Gradebook.click_total_header_menu_option("Move to Front")

      expect(Gradebook.gradebook_slick_header_columns[1]).to match("Total")
    end
  end
end

describe "Gradebook - total column menu options" do
  it_behaves_like "Gradebook - total column menu options", true
  it_behaves_like "Gradebook - total column menu options", false
end
