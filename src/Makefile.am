#
# Copyright (c) 2013 Red Hat, Inc. All rights reserved.
#
# This copyrighted material is made available to anyone wishing
# to use, modify, copy, or redistribute it subject to the terms
# and conditions of the GNU General Public License version 2.
#
# This program is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied
# warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
# PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public
# License along with this program; if not, write to the Free
# Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
# Boston, MA 02110-1301, USA.

dist_bin_SCRIPTS = \
    ep_env              \
    ep_glob             \
    ep_glob_escape      \
    ep_log_beakerlib    \
    ep_log_cook         \
    ep_log_filter       \
    ep_log_mix

install-exec-hook:
	$(SED) -e 's#\(EP_LIB_DIR=\).*#\1"$(pkgdatadir)"#' \
           -i "$(DESTDIR)$(bindir)/ep_env"
