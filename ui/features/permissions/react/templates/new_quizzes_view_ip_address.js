/*
 * Copyright (C) 2021 - present Instructure, Inc.
 *
 * This file is part of Canvas.
 *
 * Canvas is free software: you can redistribute it and/or modify it under
 * the terms of the GNU Affero General Public License as published by the Free
 * Software Foundation, version 3 of the License.
 *
 * Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
 * A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
 * details.
 *
 * You should have received a copy of the GNU Affero General Public License along
 * with this program. If not, see <http://www.gnu.org/licenses/>.
 */

import {useScope as createI18nScope} from '@canvas/i18n'
import {generateActionTemplates} from '../generateActionTemplates'

const I18n = createI18nScope('permissions_templates_83')

export const template = generateActionTemplates(
  [
    {
      title: I18n.t('New Quizzes'),
      description: I18n.t(
        'This permission allows users to view IP address information on the activity log.',
      ),
    },
  ],
  [
    {
      title: I18n.t('Account Roles'),
      description: I18n.t(
        'To allow users to view IP address information, the "Admin - add/remove permission" and the "Permissions - manage" permission must be enabled for the Quizzes.Next Service.',
      ),
    },
  ],
  [],
  [],
)
