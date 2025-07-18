# frozen_string_literal: true

#
# Copyright (C) 2014 - present Instructure, Inc.
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

require "fileutils"

module AttachmentFu # :nodoc:
  module Backends
    # Methods for file system backed attachments
    module FileSystemBackend
      def self.included(base) # :nodoc:
        base.before_update :rename_file
      end

      # Gets the full path to the filename in this format:
      #
      #   # This assumes a model name like MyModel
      #   # public/#{table_name} is the default filesystem path
      #   RAILS_ROOT/public/my_models/5/blah.jpg
      #
      # Overwrite this method in your model to customize the filename.
      # The optional thumbnail argument will output the thumbnail's filename.
      def full_filename(thumbnail = nil)
        return nil if thumbnail_name_for(thumbnail).blank?

        file_system_path = (thumbnail ? thumbnail_class : self).attachment_options[:path_prefix].to_s
        Rails.root.join(file_system_path, *partitioned_path(thumbnail_name_for(thumbnail))).to_s
      end

      # Used as the base path that #public_filename strips off full_filename to create the public path
      def base_path
        @base_path ||= Rails.public_path.to_s
      end

      # The attachment ID used in the full path of a file
      def attachment_path_id
        ((respond_to?(:parent_id) && parent_id) || id).to_i
      end

      # overrwrite this to do your own app-specific partitioning.
      # you can thank Jamis Buck for this: http://www.37signals.com/svn/archives2/id_partitioning.php
      def partitioned_path(*args)
        ("%08d" % attachment_path_id).scan(/..../) + args
      end

      # Gets the public path to the file
      # The optional thumbnail argument will output the thumbnail's filename.
      def public_filename(thumbnail = nil)
        full_filename(thumbnail).gsub(/^#{Regexp.escape(base_path)}/, "")
      end

      def authenticated_s3_url(*args)
        if args[0].is_a?(Hash)
          unless args[0][:secure].nil?
            protocol = args[0][:secure] ? "https://" : "http://"
          end
          user = args[0][:user] if args[0][:user]
          ttl = args[0][:ttl] if args[0][:ttl]
        end
        protocol ||= "#{HostUrl.protocol}://"
        "#{protocol}#{local_storage_path(user:, ttl:)}"
      end

      def filename=(value)
        value = sanitize_filename(value)
        if !new_record? && !(filename.nil? || @old_filename)
          @old_filename = full_filename
        end
        self["filename"] = value
      end

      def sanitize_filename(filename)
        if respond_to?(:root_attachment) && root_attachment&.filename
          filename = root_attachment.filename
        else
          filename = Attachment.truncate_filename(filename, 255)
          filename&.gsub!(%r{/| }, "_")
        end
        filename
      end

      def bucket_name
        "no-bucket"
      end

      # Creates a temp file from the currently saved file.
      def create_temp_file
        copy_to_temp_file full_filename
      end

      protected

      # Destroys the file.  Called in the after_destroy callback
      def destroy_file
        FileUtils.rm full_filename
        # remove directory also if it is now empty
        Dir.rmdir(File.dirname(full_filename)) if (Dir.entries(File.dirname(full_filename)) - [".", ".."]).empty?
      rescue
        logger.info "Exception destroying  #{full_filename.inspect}: [#{$!.class.name}] #{$!}"
        logger.warn $!.backtrace.collect { |b| " > #{b}" }.join("\n")
      end

      # Renames the given file before saving
      def rename_file
        # INSTRUCTURE: We don't actually want to rename Attachments.
        # The problem is that we're re-using our s3 storage if you copy
        # a file or if two files have the same md5 and size.  In that case
        # there are multiple attachments pointing to the same place on s3
        # and we don't want to get rid of the original...
        # TODO: we'll just have to figure out a different way to clean out
        # the cruft that happens because of this
        false
      end

      # Saves the file to the file system
      def save_to_storage
        if save_attachment_from_temp_path?
          # TODO: This overwrites the file if it exists, maybe have an allow_overwrite option?
          FileUtils.mkdir_p(File.dirname(full_filename))
          FileUtils.cp(temp_path, full_filename)
          File.chmod(attachment_options[:chmod] || 0o644, full_filename)
        end
        @old_filename = nil
        true
      end

      def current_data
        File.file?(full_filename) ? File.read(full_filename) : nil
      end
    end
  end
end
