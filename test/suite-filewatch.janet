# Copyright (c) 2024 Calvin Rose & contributors
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to
# deal in the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
# sell copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
# IN THE SOFTWARE.

(import ./helper :prefix "" :exit true)
(start-suite)

(assert true)

(def chan (ev/chan 1000))
(def is-win (= :windows (os/which)))
(def is-linux (= :linux (os/which)))

# Test GC
(assert-no-error "filewatch/new" (filewatch/new chan))
(gccollect)

(defn- expect
  [key value]
  (ev/with-deadline
    1
    (def event (ev/take chan))
    (when is-verbose (pp event))
    (assert event "check event")
    (assert (= value (get event key)) (string/format "got %p, expected %p" (get event key) value))))

(defn- expect-empty
  []
  (assert (zero? (ev/count chan)) "channel check empty")
  (ev/sleep 0) # turn the event loop
  (assert (zero? (ev/count chan)) "channel check empty"))

(defn spit-file
  [dir name]
  (def path (string dir "/" name))
  (spit path "test text"))

# Different operating systems report events differently. While it would be nice to
# normalize this, each system has very large limitations in what can be reported when
# compared with other systems. As such, the maximum subset of common functionality here
# is quite small. Instead, test the capabilities of each system.

# Create a file watcher on two test directories
(def fw (filewatch/new chan))
(def td1 (randdir))
(def td2 (randdir))
(rmrf td1)
(rmrf td2)
(os/mkdir td1)
(os/mkdir td2)
(case (os/which)
  :windows
  (do
    (filewatch/add fw td1 :last-write :last-access :file-name :dir-name :size :attributes :recursive)
    (filewatch/add fw td2 :last-write :last-access :file-name :dir-name :size :attributes))
  # default
  (do
    (filewatch/add fw td1 :close-write :create :delete)
    (filewatch/add fw td2 :close-write :create :delete :ignored)))
(assert-no-error "filewatch/listen no error" (filewatch/listen fw))

#
# Windows file writing
#

(when is-win
  (spit-file td1 "file1.txt")
  (expect :type :added)
  (expect :type :modified)
  (expect-empty)
  (gccollect)
  (spit-file td1 "file1.txt")
  (expect :type :modified)
  (expect :type :modified)
  (expect-empty)
  (gccollect)

  # Check td2
  (spit-file td2 "file2.txt")
  (expect :type :added)
  (expect :type :modified)
  (expect-empty)

  # Remove a file, then wait for remove event
  (rmrf (string td1 "/file1.txt"))
  (expect :type :removed)
  (expect-empty)

  # Unlisten to some events
  (filewatch/remove fw td2)

  # Check that we don't get anymore events from test directory 2
  (spit-file td2 "file2.txt")
  (expect-empty)

  # Repeat and things should still work with test directory 1
  (spit-file td1 "file1.txt")
  (expect :type :added)
  (expect :type :modified)
  (expect-empty)
  (gccollect)
  (spit-file td1 "file1.txt")
  (expect :type :modified)
  (expect :type :modified)
  (expect-empty)
  (gccollect))

#
# Linux file writing
#

(when is-linux
  (spit-file td1 "file1.txt")
  (expect :type :create)
  (expect :type :close-write)
  (expect-empty)
  (gccollect)
  (spit-file td1 "file1.txt")
  (expect :type :close-write)
  (expect-empty)
  (gccollect)

  # Check td2
  (spit-file td2 "file2.txt")
  (expect :type :create)
  (expect :type :close-write)
  (expect-empty)

  # Remove a file, then wait for remove event
  (rmrf (string td1 "/file1.txt"))
  (expect :type :delete)
  (expect-empty)

  # Unlisten to some events
  (filewatch/remove fw td2)
  (expect :type :ignored)
  (expect-empty)

  # Check that we don't get anymore events from test directory 2
  (spit-file td2 "file2.txt")
  (expect-empty)

  # Repeat and things should still work with test directory 1
  (spit-file td1 "file1.txt")
  (expect :type :create)
  (expect :type :close-write)
  (expect-empty)
  (gccollect)
  (spit-file td1 "file1.txt")
  (expect :type :close-write)
  (expect-empty)
  (gccollect))

(assert-no-error "filewatch/unlisten no error" (filewatch/unlisten fw))
(assert-no-error "cleanup 1" (rmrf td1))
(assert-no-error "cleanup 2" (rmrf td2))

(end-suite)
