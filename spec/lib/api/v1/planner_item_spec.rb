# frozen_string_literal: true

#
# Copyright (C) 2017 - present Instructure, Inc.
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

require_relative "../../../spec_helper"

describe Api::V1::PlannerItem do
  before :once do
    course_factory active_all: true

    teacher_in_course active_all: true
    @reviewer = student_in_course(course: @course, active_all: true).user
    @student = student_in_course(course: @course, active_all: true).user
    @account = @course.root_account
    for_course = { course: @course }

    assignment_quiz [], for_course
    group_assignment_discussion for_course
    assignment_model for_course.merge(submission_types: "online_text_entry")
    @assignment.workflow_state = "published"
    @assignment.save!

    @teacher_override = planner_override_model(plannable: @assignment, user: @teacher)
    @student_override = planner_override_model(plannable: @assignment, user: @student, marked_complete: true)
  end

  let(:planner_item_harness) do
    Class.new do
      include Api::V1::PlannerItem

      def submission_json(*); end

      def named_context_url(*)
        "named_context_url"
      end

      def course_assignment_submission_url(*)
        "course_assignment_submission_url"
      end

      def course_assignment_url(*)
        "course_assignment_url"
      end

      def calendar_url_for(*); end
    end
  end

  let(:api) { planner_item_harness.new }
  let(:session) { double }

  describe ".planner_item_json" do
    it "returns with a plannable_date for the respective item" do
      asg_due_at = 1.week.ago
      asg = assignment_model course: @course, submission_types: "online_text_entry", due_at: asg_due_at
      asg_hash = api.planner_item_json(asg, @student, session)
      expect(asg_hash[:plannable_date]).to eq asg_due_at
      expect(asg_hash[:plannable]).to include("id", "title", "due_at", "points_possible")

      dt_todo_date = 1.week.from_now
      dt = discussion_topic_model course: @course, todo_date: dt_todo_date
      dt_hash = api.planner_item_json(dt, @student, session)
      expect(dt_hash[:plannable_date]).to eq dt_todo_date
      expect(dt_hash[:plannable]).to include("id", "title", "todo_date", "assignment_id")

      wiki_todo_date = 1.day.ago
      wiki = wiki_page_model course: @course, todo_date: wiki_todo_date
      wiki_hash = api.planner_item_json(wiki, @student, session)
      expect(wiki_hash[:plannable_date]).to eq wiki_todo_date
      expect(wiki_hash[:plannable]).to include("id", "title", "todo_date")

      annc_post_date = 1.day.from_now
      annc = announcement_model context: @course, posted_at: annc_post_date
      annc_hash = api.planner_item_json(annc, @student, session)
      expect(annc_hash[:plannable_date]).to eq annc_post_date
      expect(annc_hash[:plannable]).not_to include "todo_date"
      expect(annc_hash[:plannable]).to include("id", "title", "created_at")

      event_start_date = 2.days.from_now
      event = calendar_event_model(start_at: event_start_date)
      event_hash = api.planner_item_json(event, @student, session)
      expect(event_hash[:plannable_date]).to eq event_start_date
      expect(event_hash[:plannable].keys).to include("id", "title", "start_at", "end_at", "all_day", "description")
    end

    it "returns with a context_name and context_image for the respective item" do
      asg_hash = api.planner_item_json(@assignment, @student, session)
      expect(asg_hash[:context_name]).to eq @course.name
      expect(asg_hash[:context_image]).to be_nil

      @course.name = "test course name"
      expect(api.planner_item_json(@assignment, @student, session)[:context_name]).to eq "test course name"

      @course.image_url = "path/to/course/image.png"
      expect(api.planner_item_json(@assignment, @student, session)[:context_image]).to eq "path/to/course/image.png"
    end

    describe "calendar events with an online meeting url" do
      before(:once) do
        @meeting_urls = ["https://myschool.zoom.us/123456", "https://myschool.zoom.us/j/123456", "https://myschool.zoom.us/my/123456"]
      end

      it "includes it in the result if found in the event description" do
        event_start_date = 2.days.from_now
        @meeting_urls.each do |zurl|
          event = calendar_event_model(start_at: event_start_date, description: "zoom at #{zurl} for this thing")
          event_hash = api.planner_item_json(event, @student, session)
          expect(event_hash[:plannable][:online_meeting_url]).to eq zurl
        end
      end

      it "includes it in the event if found in the event location" do
        event_start_date = 2.days.from_now
        @meeting_urls.each do |zurl|
          event = calendar_event_model(start_at: event_start_date, location_name: "zoom at #{zurl} for this thing")
          event_hash = api.planner_item_json(event, @student, session)
          expect(event_hash[:plannable][:online_meeting_url]).to eq zurl
        end
      end

      context "default meeting url regex" do
        let(:valid_links) do
          %w[
            https://instructure.zoom.us/my/abcd.12345
            https://instructure.zoom.us/j/9585021282
            https://us01.zoom.us/j/9585001282?
            https://instructure.zoom.us/j/9585021282?pwd=NlRIRURaRlRmTC9kVUU2QnIwQkJZZz09
            https://instr-ucture.zoom.us/my/12345
            https://instr-ucture.zoom.us/j/9585021282
            https://teams.microsoft.com/l/meetup-join/19%3ameeting_MjAyMjU4Y2QtZTc0Mi00OTI1LTllYTUtNjEzNTBhMjY3OTZi%40thread.v2/0?context=%7B%22Tid%22%3A%22b8e866dc-ae4d-482d-8ebb-6ef626b97a42%22%2C%22Oid%22%3A%22ac200842-2ec5-494e-83db-dfddc8939907%22%7D
            https://teams.live.com/meet/93298311589140
            https://meet146.webex.com/meet/pr-._25535050184
            https://meet146.webex.com/meet146/j.php?MTID=mb0f63c6586178c903f161b109886066b
            https://meet-146.webex.com/meet/pr-._25535050184
            https://meet.google.com/sbs-ycbe-yhu
            https://myschool.instructure.com/courses/17/conferences/19/join
          ]
        end

        let(:invalid_links) do
          %w[
            http://instructure.zoom.us/my/abcd.12345
            https://us01.zoom.us/j/abc123
            https://zoom.us/j/9585021282?pwd=NlRIRURaRlRmTC9kVUU2QnIwQkJZZz09
            https://teams.live.com/join/93298311589140
            https://meet146.webex.com/join/pr-._25535050184
            https://meet146.webex.com/meet146/j?MTID=mb0f63c6586178c903f161b109886066b
            https://google.com/sbs-ycbe-yhu
            https://instructure.com
            not
            even
            a
            link
            .
            zoom
            http://example.com/124?pwd=1234
            https://me-et.google.com/sbs-ycbe-yhu
            https://tea-ms.microsoft.com/l/meetup-join/19%3ameeting_MjAyMjU4Y2QtZTc0Mi00OTI1LTllYTUtNjEzNTBhMjY3OTZi%40thread.v2/0?context=%7B%22Tid%22%3A%22b8e866dc-ae4d-482d-8ebb-6ef626b97a42%22%2C%22Oid%22%3A%22ac200842-2ec5-494e-83db-dfddc8939907%22%7D
            https://teams.micro-soft.com/l/meetup-join/19%3ameeting_MjAyMjU4Y2QtZTc0Mi00OTI1LTllYTUtNjEzNTBhMjY3OTZi%40thread.v2/0?context=%7B%22Tid%22%3A%22b8e866dc-ae4d-482d-8ebb-6ef626b97a42%22%2C%22Oid%22%3A%22ac200842-2ec5-494e-83db-dfddc8939907%22%7D
            https://tea-ms.live.com/meet/93298311589140
            https://myschool.instructure.com/courses/17/conferences
          ]
        end

        it "matches valid video conferencing links" do
          valid_links.each do |l|
            event = calendar_event_model(start_at: 1.day.from_now, description: l)
            event_hash = api.planner_item_json(event, @student, session)
            expect(event_hash[:plannable][:online_meeting_url]).to eq l
          end
        end

        it "does not match invalid links" do
          invalid_links.each do |l|
            event = calendar_event_model(start_at: 1.day.from_now, description: l)
            event_hash = api.planner_item_json(event, @student, session)
            expect(event_hash[:plannable][:online_meeting_url]).to be_nil
          end
        end
      end
    end

    context "planner overrides" do
      it "returns the planner override id" do
        teacher_hash = api.planner_item_json(@assignment, @teacher, session)
        student_hash = api.planner_item_json(@assignment, @student, session)

        expect(teacher_hash[:planner_override][:id]).to eq @teacher_override.id
        expect(student_hash[:planner_override][:id]).to eq @student_override.id
      end

      it "has a nil planner_override value" do
        json = api.planner_item_json(@quiz.assignment, @student, session)
        expect(json[:planner_override]).to be_nil
      end
    end

    context "peer reviews" do
      it "includes submissions needing peer review" do
        submission = @assignment.submit_homework(@student, body: "the stuff")
        @peer_review = @assignment.assign_peer_review(@reviewer, @student)
        json = api.planner_item_json(@peer_review, @reviewer, session)
        expect(json[:plannable_type]).to eq "assessment_request"
        expect(json[:plannable][:title]).to eq @assignment.title
        expect(json[:plannable][:todo_date]).to eq submission.cached_due_date
      end

      it "includes the assignment url if the student has not submitted their assignment" do
        submission = @assignment.submit_homework(@student, body: "the stuff")
        assessor_submission = @assignment.find_or_create_submission(@reviewer)
        @peer_review = AssessmentRequest.create!(
          assessor: @reviewer,
          assessor_asset: assessor_submission,
          asset: submission,
          user: @student
        )
        json = api.planner_item_json(@peer_review, @reviewer, session)
        expected_url = "course_assignment_url"
        expect(json[:html_url]).to eq expected_url
      end

      it "includes the submission url if the student has submitted their assignment" do
        assessor_submission = @assignment.submit_homework(@reviewer, body: "reviewer submission")
        submission = @assignment.submit_homework(@student, body: "the stuff")
        @peer_review = AssessmentRequest.create!(
          assessor: @reviewer,
          assessor_asset: assessor_submission,
          asset: submission,
          user: @student
        )
        json = api.planner_item_json(@peer_review, @reviewer, session)
        expected_url = "/courses/#{@assignment.course.id}/assignments/#{@assignment.id}/submissions/#{@student.id}"
        expect(json[:html_url]).to eq expected_url
      end

      it "includes the anonymized submission url when anonymous peer reviews" do
        @assignment.update!(anonymous_peer_reviews: true)
        assessor_submission = @assignment.submit_homework(@reviewer, body: "reviewer submission")
        submission = @assignment.submit_homework(@student, body: "the stuff")
        @peer_review = AssessmentRequest.create!(
          assessor: @reviewer,
          assessor_asset: assessor_submission,
          asset: submission,
          user: @student
        )
        json = api.planner_item_json(@peer_review, @reviewer, session)
        expected_url = "/courses/#{@course.id}/assignments/#{@assignment.id}/anonymous_submissions/#{submission.anonymous_id}"
        expect(json[:html_url]).to eq expected_url
      end

      context "assignments_2_student feature flag" do
        before do
          @course.enable_feature!(:assignments_2_student)
        end

        it "returns enhanced peer review url when feature flag is enabled" do
          submission = @assignment.submit_homework(@student, body: "the stuff")
          assessor_submission = @assignment.find_or_create_submission(@reviewer)
          @peer_review = AssessmentRequest.create!(
            assessor: @reviewer,
            assessor_asset: assessor_submission,
            asset: submission,
            user: @student
          )
          json = api.planner_item_json(@peer_review, @reviewer, session)
          expected_url = "course_assignment_url"
          expect(json[:html_url]).to eq expected_url
        end
      end
    end

    context "dicussion checkpoints" do
      before :once do
        @course.account.enable_feature!(:discussion_checkpoints)
        course_with_student(active_all: true)
        @checkpoint_topic, @checkpoint_entry = graded_discussion_topic_with_checkpoints(context: @course)
      end

      it "returns checkpoints" do
        json = api.planner_item_json(@checkpoint_topic, @student, session)
        expect(json[:plannable_type]).to eq "sub_assignment"
        expect(json[:plannable][:title]).to eq @checkpoint_topic.title
      end

      it "includes number of required replies" do
        json = api.planner_item_json(@checkpoint_topic, @student, session)
        expect(json[:details][:reply_to_entry_required_count]).to eq 3
      end

      it "includes sub assignment tag" do
        json = api.planner_item_json(@checkpoint_topic, @student, session)
        expect(json[:plannable][:sub_assignment_tag]).to eq "reply_to_topic"
      end
    end

    describe "#submission_statuses_for" do
      it "returns the submission statuses for the learning object" do
        json = api.planner_item_json(@assignment, @student, session)
        expect(json).to have_key(:submissions)
        expect(%i[submitted excused graded late missing needs_grading has_feedback redo_request].all? do |k|
          json[:submissions].key?(k)
        end).to be true
      end

      it "indicates that an assignment is submitted" do
        @assignment.submit_homework(@student, body: "b")

        json = api.planner_item_json(@assignment, @student, session)
        expect(json[:submissions][:submitted]).to be true
      end

      it "indicates that an assignment is missing" do
        @assignment.update!(due_at: 1.week.ago)

        json = api.planner_item_json(@assignment, @student, session)
        expect(json[:submissions][:missing]).to be true
      end

      it "indicates that an assignment is excused" do
        submission = @assignment.submit_homework(@student, body: "b")
        submission.excused = true
        submission.save!

        json = api.planner_item_json(@assignment, @student, session)
        expect(json[:submissions][:excused]).to be true
      end

      it "indicates that a graded assignment is graded" do
        submission = @assignment.submit_homework(@student, body: "o")
        submission.update(score: 10)
        submission.grade_it!

        json = api.planner_item_json(@assignment, @student, session)
        expect(json[:submissions][:graded]).to be true
        # just because it's graded, doesn't mean there's feedback
        expect(json[:submissions][:has_feedback]).to be false
      end

      it "indicates that an assignment is late" do
        @assignment.update!(due_at: 1.week.ago)
        @assignment.submit_homework(@student, body: "d")

        json = api.planner_item_json(@assignment, @student, session)
        expect(json[:submissions][:late]).to be true
      end

      it "indicates that an assignment needs grading" do
        @assignment.submit_homework(@student, body: "y")

        json = api.planner_item_json(@assignment, @student, session)
        expect(json[:submissions][:needs_grading]).to be true
      end

      it "indicates that a graded assignment with comment has feedback and is graded" do
        submission = @assignment.submit_homework(@student, body: "the stuff")
        submission.add_comment(user: @teacher, comment: "nice work, fam")
        submission.update(score: 10)
        submission.grade_it!

        json = api.planner_item_json(@assignment, @student, session)
        expect(json[:submissions][:has_feedback]).to be true
        expect(json[:submissions][:graded]).to be true
      end

      it "indicates that a not-yet-graded assignment has feedback" do
        submission = @assignment.submit_homework(@student, body: "the stuff")
        submission.add_comment(user: @teacher, comment: "nice work, fam")
        submission.grade_it!

        json = api.planner_item_json(@assignment, @student, session)
        expect(json[:submissions][:has_feedback]).to be true
        expect(json[:submissions][:graded]).to be false
      end

      it "includes comment data for assignments with feedback" do
        submission = @assignment.submit_homework(@student, body: "the stuff")
        submission.add_comment(user: @teacher, comment: "nice work, fam")
        submission.update(score: 10)
        submission.grade_it!

        json = api.planner_item_json(@assignment, @student, session)
        expect(json[:submissions][:has_feedback]).to be true
        expect(json[:submissions][:feedback]).to eq({
                                                      comment: "nice work, fam",
                                                      author_name: @teacher.name,
                                                      author_avatar_url: @teacher.avatar_url,
                                                      is_media: false
                                                    })
      end

      it "includes old comment data for assignments with old feedback" do
        Timecop.travel(4.months.ago) do
          assignment_model(course: @course, submission_types: "online_text_entry")
          @assignment.workflow_state = "published"
          @assignment.save!

          submission = @assignment.submit_homework(@student, body: "the stuff")
          # created_at is set by the database, which doesn't know about Timecop
          submission.created_at = Time.zone.now
          submission.add_comment(user: @teacher, comment: "nice work, fam")
          submission.update(score: 10)
          submission.grade_it!
        end
        json = api.planner_item_json(@assignment, @student, session, { due_after: 5.months.ago })
        expect(json[:submissions][:has_feedback]).to be true
        expect(json[:submissions][:feedback]).to eq({
                                                      comment: "nice work, fam",
                                                      author_name: @teacher.name,
                                                      author_avatar_url: @teacher.avatar_url,
                                                      is_media: false
                                                    })
      end

      it "includes comment data from before the assignment is due" do
        assignment_model(course: @course, submission_types: "online_text_entry", due_at: 2.weeks.from_now)
        @assignment.workflow_state = "published"
        @assignment.save!
        Timecop.travel(4.weeks.ago) do
          submission = @assignment.submit_homework(@student, body: "the stuff")
          # created_at is set by the database, which doesn't know about Timecop
          submission.created_at = Time.zone.now
          submission.add_comment(user: @teacher, comment: "nice work, fam")
          submission.update(score: 10)
          submission.grade_it!
        end
        json = api.planner_item_json(@assignment, @student, session, { due_after: 3.weeks.ago })
        expect(json[:submissions][:has_feedback]).to be true
        expect(json[:submissions][:feedback]).to eq({
                                                      comment: "nice work, fam",
                                                      author_name: @teacher.name,
                                                      author_avatar_url: @teacher.avatar_url,
                                                      is_media: false
                                                    })
      end

      it "discards comments by the user herself" do
        submission = @assignment.submit_homework(@student, body: "the stuff")
        submission.add_comment(user: @teacher, comment: "nice work, fam")
        submission.add_comment(user: @student, comment: "I know, right?")
        submission.update(score: 10)
        submission.grade_it!

        json = api.planner_item_json(@assignment, @student, session)
        expect(json[:submissions][:has_feedback]).to be true
        expect(json[:submissions][:feedback]).to eq({
                                                      comment: "nice work, fam",
                                                      author_name: @teacher.name,
                                                      author_avatar_url: @teacher.avatar_url,
                                                      is_media: false
                                                    })
      end

      it "selects the most recent comment" do
        submission = @assignment.submit_homework(@student, body: "the stuff")
        submission.add_comment(user: @teacher, comment: "nice work, fam")
        submission.add_comment(user: @student, comment: "I know, right?")
        submission.add_comment(user: @teacher, comment: "don't let it go to your head.")
        submission.update(score: 10)
        submission.grade_it!

        json = api.planner_item_json(@assignment, @student, session)
        expect(json[:submissions][:has_feedback]).to be true
        expect(json[:submissions][:feedback]).to eq({
                                                      comment: "don't let it go to your head.",
                                                      author_name: @teacher.name,
                                                      author_avatar_url: @teacher.avatar_url,
                                                      is_media: false
                                                    })
      end

      it "includes is_media if comment has a media_comment_id" do
        submission = @assignment.submit_homework(@student, body: "the stuff")
        submission.add_comment(user: @teacher, comment: "nice work, fam", media_comment_id: 2)
        submission.update(score: 10)
        submission.grade_it!

        json = api.planner_item_json(@assignment, @student, session)
        expect(json[:submissions][:has_feedback]).to be true
        expect(json[:submissions][:feedback]).to eq({
                                                      comment: "nice work, fam",
                                                      author_name: @teacher.name,
                                                      author_avatar_url: @teacher.avatar_url,
                                                      is_media: true
                                                    })
      end

      it "does not include an author_name or author_avatar_url if comment is anonymous" do
        @assignment.anonymous_peer_reviews = true
        @assignment.save!
        submission = @assignment.submit_homework(@student, body: "the stuff")
        submission.add_comment(user: @reviewer, comment: "nice work, fam")
        submission.update(score: 10)
        submission.grade_it!

        json = api.planner_item_json(@assignment, @student, session)
        expect(json[:submissions][:has_feedback]).to be true
        expect(json[:submissions][:feedback].keys).not_to include(:author_name, :author_avatar_url)
      end

      context "discussion checkpoints/sub_assignments" do
        before do
          course_with_student(active_all: true)
          course_with_teacher(course: @course, active_all: true)
          @course.account.enable_feature!(:discussion_checkpoints)
          @reply_to_topic, @reply_to_entry = graded_discussion_topic_with_checkpoints(context: @course, title: "Discussion with Checkpoints")
        end

        it "indicates that a graded sub_assignment with parent assignment comment has feedback and is graded" do
          @reply_to_topic.submit_homework @student, body: "checkpoint submission for #{@student.name}"
          @reply_to_topic.grade_student(@student, grade: 5, grader: @teacher)
          @topic.assignment.submission_for_student(@student).add_comment(user: @teacher, comment: "nice work")

          json = api.planner_item_json(@reply_to_topic, @student, session)
          expect(json[:submissions][:has_feedback]).to be true
          expect(json[:submissions][:graded]).to be true
        end

        it "indicates that a not-yet-graded sub_assignment with parent assignment comment has feedback" do
          @reply_to_topic.submit_homework @student, body: "checkpoint submission for #{@student.name}"
          @topic.assignment.submission_for_student(@student).add_comment(user: @teacher, comment: "nice work")

          json = api.planner_item_json(@assignment, @student, session)
          expect(json[:submissions][:has_feedback]).to be true
          expect(json[:submissions][:graded]).to be false
        end

        it "includes comment data from the parent assignment for sub_assignment with feedback" do
          @reply_to_topic.submit_homework @student, body: "checkpoint submission for #{@student.name}"
          @topic.assignment.submission_for_student(@student).add_comment(user: @teacher, comment: "nice work")

          json = api.planner_item_json(@reply_to_topic, @student, session)
          expect(json[:submissions][:has_feedback]).to be true
          expect(json[:submissions][:feedback]).to eq({
                                                        comment: "nice work",
                                                        author_name: @teacher.name,
                                                        author_avatar_url: @teacher.avatar_url,
                                                        is_media: false
                                                      })
        end
      end
    end
  end

  describe "#new_activity" do
    before :once do
      discussion_topic_model
    end

    it "returns true for assignments with new grades" do
      group_discussion_assignment
      graded_submission(@quiz, @student)
      graded_submission_model(assignment: @assignment, user: @student).update(score: 5)
      graded_submission_model(assignment: @topic.assignment, user: @student).update(score: 5)
      Assignment.active.each(&:post_submissions)
      expect(api.planner_item_json(@quiz.reload, @student, session)[:new_activity]).to be true
      expect(api.planner_item_json(@assignment.reload, @student, session)[:new_activity]).to be true
      expect(api.planner_item_json(@topic.reload, @student, session)[:new_activity]).to be true
    end

    it "returns true for assignments with new feedback" do
      student_in_course active_all: true
      submission_model(assignment: @quiz.assignment, user: @student).add_comment(author: @teacher, comment: "hi")
      submission_model(assignment: @assignment, user: @student).add_comment(author: @teacher, comment: "hi")
      submission_model(assignment: @topic.assignment, user: @student).add_comment(author: @teacher, comment: "hi")
      Assignment.active.each(&:post_submissions)
      expect(api.planner_item_json(@quiz.reload, @student, session)[:new_activity]).to be true
      expect(api.planner_item_json(@assignment.reload, @student, session)[:new_activity]).to be true
      expect(api.planner_item_json(@topic.reload, @student, session)[:new_activity]).to be true
    end

    it "returns true for unread discussions" do
      expect(api.planner_item_json(@topic, @student, session)[:new_activity]).to be true
    end

    it "returns false for a read discussion" do
      @topic.change_read_state("read", @student)
      expect(api.planner_item_json(@topic, @student, session)[:new_activity]).to be false
    end

    it "returns false for discussions with replies that has been marked read" do
      @topic.reply_from(user: @teacher, text: "reply")
      @topic.change_all_read_state("read", @student)
      expect(api.planner_item_json(@topic, @student, session)[:new_activity]).to be false
    end

    it "returns true for discussions with new replies" do
      @group_category = nil
      announcement_model(context: @course)
      @a.change_read_state("read", @student)
      @topic.change_read_state("read", @student)
      @a.reply_from(user: @teacher, text: "reply")
      @topic.reply_from(user: @teacher, text: "reply")
      expect(api.planner_item_json(@a, @student, session)[:new_activity]).to be true
      expect(api.planner_item_json(@topic, @student, session)[:new_activity]).to be true
    end

    it "returns false for items without new activity" do
      student_in_course active_all: true
      expect(api.planner_item_json(@quiz, @student, session)[:new_activity]).to be false
      expect(api.planner_item_json(@assignment, @student, session)[:new_activity]).to be false
    end

    it "returns false for items that cannot have new activity" do
      planner_note_model(user: @student)
      expect(api.planner_item_json(@planner_note, @student, session)[:new_activity]).to be false
    end

    context "discussion checkpoints/sub_assignments" do
      before do
        course_with_student(active_all: true)
        course_with_teacher(course: @course, active_all: true)
        @course.account.enable_feature!(:discussion_checkpoints)
        @reply_to_topic, @reply_to_entry = graded_discussion_topic_with_checkpoints(context: @course, title: "Discussion with Checkpoints")
      end

      it "returns true for sub_assignments with new grades" do
        @reply_to_topic.submit_homework @student, body: "checkpoint submission for #{@student.name}"
        @reply_to_topic.grade_student(@student, grade: 5, grader: @teacher)
        @reply_to_entry.submit_homework @student, body: "checkpoint submission for #{@student.name}"
        @reply_to_entry.grade_student(@student, grade: 5, grader: @teacher)

        json = api.planner_item_json(@reply_to_topic.reload, @student, session)
        expect(json[:new_activity]).to be true
        json = api.planner_item_json(@reply_to_entry.reload, @student, session)
        expect(json[:new_activity]).to be true
      end

      it "returns true for sub_assignments with new feedback" do
        @reply_to_topic.submit_homework @student, body: "checkpoint submission for #{@student.name}"
        @reply_to_entry.submit_homework @student, body: "checkpoint submission for #{@student.name}"
        @topic.assignment.submission_for_student(@student).add_comment(user: @teacher, comment: "nice work")

        json = api.planner_item_json(@reply_to_topic.reload, @student, session)
        expect(json[:new_activity]).to be true
        json = api.planner_item_json(@reply_to_entry.reload, @student, session)
        expect(json[:new_activity]).to be true
      end

      it "includes unread_count property from discussion topics" do
        @reply_to_topic.submit_homework @student, body: "checkpoint submission for #{@student.name}"
        json = api.planner_item_json(@reply_to_topic, @student, session)
        expect(json[:plannable][:unread_count]).to eq 0
        expect(json[:plannable][:read_state]).to eq "unread"
      end
    end
  end

  describe "#html_url" do
    it "links to an assignment's submission if appropriate" do
      assignment_model course: @course, submission_types: "online_text_entry"
      expect(api.planner_item_json(@assignment, @student, session)[:html_url]).to eq "named_context_url"
      @assignment.submit_homework(@student, body: "...")
      expect(api.planner_item_json(@assignment, @student, session)[:html_url]).to eq "course_assignment_submission_url"
    end

    it "links to a graded discussion topic's submission if appropriate" do
      group_discussion_assignment
      expect(api.planner_item_json(@topic.assignment, @student, session)[:html_url]).to eq "named_context_url"
      graded_submission_model(assignment: @topic.assignment, user: @student).update(score: 5)
      expect(api.planner_item_json(@topic.assignment, @student, session)[:html_url]).to eq "course_assignment_submission_url"
    end

    it "links to a graded discussion with checkpoints submission if appropriate" do
      @course.account.enable_feature!(:discussion_checkpoints)
      @checkpoint_topic, _checkpoint_entry = graded_discussion_topic_with_checkpoints(context: @course)
      expect(api.planner_item_json(@checkpoint_topic, @student, session)[:html_url]).to eq "named_context_url"
      graded_submission_model(assignment: @checkpoint_topic, user: @student).update(score: 5)
      expect(api.planner_item_json(@checkpoint_topic, @student, session)[:html_url]).to eq "course_assignment_submission_url"
    end
  end

  describe "sharding" do
    specs_require_sharding

    context "discussion_topics" do
      it "returns true for unread other shard discussions" do
        topic1 = discussion_topic_model
        topic2 = @shard1.activate do
          account = account_model
          course = account.courses.create!
          discussion_topic_model(context: course)
        end
        json = api.planner_items_json([topic1, topic2], @student, session)
        expect(json.pluck(:plannable_id)).to match_array([topic1.id, topic2.id])
      end
    end
  end

  describe "submission comments" do
    before do
      @submission = @assignment.submit_homework(@student, body: "my submission")
      @html_comment = @submission.add_comment(author: @teacher, comment: "<div>html comment</div>", attempt: nil)
    end

    it "if use_html_comment true returns submission comments with html tags" do
      json = api.planner_items_json([@assignment], @student, session, { use_html_comment: true })
      expect(json.first[:submissions][:feedback][:comment]).to eq("<div>html comment</div>")
    end

    it "if use_html_comment false returns submission comments without htl tags" do
      json = api.planner_items_json([@assignment], @student, session)
      expect(json.first[:submissions][:feedback][:comment]).to eq("html comment")
    end
  end
end
