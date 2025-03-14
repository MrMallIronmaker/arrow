# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.


#' @title RecordBatchReader classes
#' @description Apache Arrow defines two formats for [serializing data for interprocess
#' communication
#' (IPC)](https://arrow.apache.org/docs/format/Columnar.html#serialization-and-interprocess-communication-ipc):
#' a "stream" format and a "file" format, known as Feather.
#' `RecordBatchStreamReader` and `RecordBatchFileReader` are
#' interfaces for accessing record batches from input sources in those formats,
#' respectively.
#'
#' For guidance on how to use these classes, see the examples section.
#'
#' @seealso [read_ipc_stream()] and [read_feather()] provide a much simpler interface
#' for reading data from these formats and are sufficient for many use cases.
#' @usage NULL
#' @format NULL
#' @docType class
#' @section Factory:
#'
#' The `RecordBatchFileReader$create()` and `RecordBatchStreamReader$create()`
#' factory methods instantiate the object and
#' take a single argument, named according to the class:
#'
#' - `file` A character file name, raw vector, or Arrow file connection object
#'    (e.g. [RandomAccessFile]).
#' - `stream` A raw vector, [Buffer], or [InputStream].
#'
#' @section Methods:
#'
#' - `$read_next_batch()`: Returns a `RecordBatch`, iterating through the
#'   Reader. If there are no further batches in the Reader, it returns `NULL`.
#' - `$schema`: Returns a [Schema] (active binding)
#' - `$batches()`: Returns a list of `RecordBatch`es
#' - `$read_table()`: Collects the reader's `RecordBatch`es into a [Table]
#' - `$get_batch(i)`: For `RecordBatchFileReader`, return a particular batch
#'    by an integer index.
#' - `$num_record_batches()`: For `RecordBatchFileReader`, see how many batches
#'    are in the file.
#'
#' @rdname RecordBatchReader
#' @name RecordBatchReader
#' @include arrow-package.R
#' @examplesIf arrow_available()
#' tf <- tempfile()
#' on.exit(unlink(tf))
#'
#' batch <- record_batch(chickwts)
#'
#' # This opens a connection to the file in Arrow
#' file_obj <- FileOutputStream$create(tf)
#' # Pass that to a RecordBatchWriter to write data conforming to a schema
#' writer <- RecordBatchFileWriter$create(file_obj, batch$schema)
#' writer$write(batch)
#' # You may write additional batches to the stream, provided that they have
#' # the same schema.
#' # Call "close" on the writer to indicate end-of-file/stream
#' writer$close()
#' # Then, close the connection--closing the IPC message does not close the file
#' file_obj$close()
#'
#' # Now, we have a file we can read from. Same pattern: open file connection,
#' # then pass it to a RecordBatchReader
#' read_file_obj <- ReadableFile$create(tf)
#' reader <- RecordBatchFileReader$create(read_file_obj)
#' # RecordBatchFileReader knows how many batches it has (StreamReader does not)
#' reader$num_record_batches
#' # We could consume the Reader by calling $read_next_batch() until all are,
#' # consumed, or we can call $read_table() to pull them all into a Table
#' tab <- reader$read_table()
#' # Call as.data.frame to turn that Table into an R data.frame
#' df <- as.data.frame(tab)
#' # This should be the same data we sent
#' all.equal(df, chickwts, check.attributes = FALSE)
#' # Unlike the Writers, we don't have to close RecordBatchReaders,
#' # but we do still need to close the file connection
#' read_file_obj$close()
RecordBatchReader <- R6Class("RecordBatchReader",
  inherit = ArrowObject,
  public = list(
    read_next_batch = function() RecordBatchReader__ReadNext(self),
    batches = function() RecordBatchReader__batches(self),
    read_table = function() Table__from_RecordBatchReader(self),
    export_to_c = function(stream_ptr) ExportRecordBatchReader(self, stream_ptr)
  ),
  active = list(
    schema = function() RecordBatchReader__schema(self)
  )
)

#' @export
head.RecordBatchReader <- function(x, n = 6L, ...) {
  # Negative n requires knowing nrow(x), which requires consuming the whole RBR
  assert_that(n >= 0)
  RecordBatchReader__Head(x, n)
}

#' @export
tail.RecordBatchReader <- function(x, n = 6L, ...) {
  tail_from_batches(x$batches(), n)
}

#' @rdname RecordBatchReader
#' @usage NULL
#' @format NULL
#' @export
RecordBatchStreamReader <- R6Class("RecordBatchStreamReader", inherit = RecordBatchReader)
RecordBatchStreamReader$create <- function(stream) {
  if (inherits(stream, c("raw", "Buffer"))) {
    # TODO: deprecate this because it doesn't close the connection to the Buffer
    # (that's a problem, right?)
    stream <- BufferReader$create(stream)
  }
  assert_is(stream, "InputStream")
  ipc___RecordBatchStreamReader__Open(stream)
}
#' @include arrowExports.R
RecordBatchReader$import_from_c <- RecordBatchStreamReader$import_from_c <- ImportRecordBatchReader

#' @rdname RecordBatchReader
#' @usage NULL
#' @format NULL
#' @export
RecordBatchFileReader <- R6Class("RecordBatchFileReader",
  inherit = ArrowObject,
  # Why doesn't this inherit from RecordBatchReader in C++?
  # Origin: https://github.com/apache/arrow/pull/679
  public = list(
    get_batch = function(i) {
      ipc___RecordBatchFileReader__ReadRecordBatch(self, i)
    },
    batches = function() {
      ipc___RecordBatchFileReader__batches(self)
    },
    read_table = function() Table__from_RecordBatchFileReader(self)
  ),
  active = list(
    num_record_batches = function() ipc___RecordBatchFileReader__num_record_batches(self),
    schema = function() ipc___RecordBatchFileReader__schema(self)
  )
)
RecordBatchFileReader$create <- function(file) {
  if (inherits(file, c("raw", "Buffer"))) {
    # TODO: deprecate this because it doesn't close the connection to the Buffer
    # (that's a problem, right?)
    file <- BufferReader$create(file)
  }
  assert_is(file, "InputStream")
  ipc___RecordBatchFileReader__Open(file)
}
