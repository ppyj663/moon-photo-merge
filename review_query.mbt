///|
/// Sort order available to the local review page and other consumers.
pub(all) enum ReviewSort {
  PathAscending
  NameAscending
  SizeDescending
  SimilarityAscending
  CategoryThenPath
} derive(Eq)

///|
pub extend ReviewSort with Eq::{not_equal, equal}

///|
pub(all) struct ReviewQuery {
  text : String
  kind : Kind?
  minimum_size : Int32?
  maximum_size : Int32?
  sort : ReviewSort
  offset : Int32
  page_size : Int32
}

///|
pub(all) struct ReviewPage {
  rows : Array[ReviewRow]
  total_matches : Int32
  offset : Int32
  page_size : Int32
  page_count : Int32
  has_previous : Bool
  has_next : Bool
}

///|
/// Default query for a fresh report view: all rows by original path, first
/// 100 entries. Pagination is available to consumers that render large scans.
pub fn default_review_query() -> ReviewQuery {
  {
    text: "",
    kind: None,
    minimum_size: None,
    maximum_size: None,
    sort: PathAscending,
    offset: 0,
    page_size: 100,
  }
}

///|
fn query_matches(row : ReviewRow, query : ReviewQuery, needle : String) -> Bool {
  let matches_text = needle == "" ||
    row.path.to_lower().contains(needle) ||
    row.name.to_lower().contains(needle) ||
    row.kind.label().contains(needle)
  let matches_kind = match query.kind {
    Some(kind) => row.kind == kind
    None => true
  }
  let matches_minimum = match query.minimum_size {
    Some(minimum) => row.size >= minimum
    None => true
  }
  let matches_maximum = match query.maximum_size {
    Some(maximum) => row.size <= maximum
    None => true
  }
  matches_text && matches_kind && matches_minimum && matches_maximum
}

///|
fn kind_order(kind : Kind) -> Int32 {
  match kind {
    New => 0
    Similar => 1
    Conflict => 2
    Exact => 3
    Unreadable => 4
  }
}

///|
fn distance_order(row : ReviewRow) -> Int32 {
  match row.similarity_distance {
    Some(distance) => distance
    None => 178
  }
}

///|
fn review_row_precedes(
  left : ReviewRow,
  right : ReviewRow,
  sort : ReviewSort,
) -> Bool {
  match sort {
    PathAscending =>
      left.path.lexical_compare(right.path) < 0 ||
      (left.path == right.path && left.name.lexical_compare(right.name) < 0)
    NameAscending =>
      left.name.lexical_compare(right.name) < 0 ||
      (left.name == right.name && left.path.lexical_compare(right.path) < 0)
    SizeDescending =>
      left.size > right.size ||
      (left.size == right.size && left.path.lexical_compare(right.path) < 0)
    SimilarityAscending =>
      distance_order(left) < distance_order(right) ||
      (
        distance_order(left) == distance_order(right) &&
        left.path.lexical_compare(right.path) < 0
      )
    CategoryThenPath =>
      kind_order(left.kind) < kind_order(right.kind) ||
      (
        kind_order(left.kind) == kind_order(right.kind) &&
        left.path.lexical_compare(right.path) < 0
      )
  }
}

///|
/// Filter, sort and page plan rows. Negative size bounds are treated as zero;
/// an inverted range returns an empty page. Page sizes are clamped to 1–500.
pub fn query_review_rows(
  rows : Array[ReviewRow],
  query : ReviewQuery,
) -> ReviewPage {
  let minimum = match query.minimum_size {
    Some(value) => Some(value.max(0))
    None => None
  }
  let maximum = match query.maximum_size {
    Some(value) => Some(value.max(0))
    None => None
  }
  let normalized = {
    text: query.text,
    kind: query.kind,
    minimum_size: minimum,
    maximum_size: maximum,
    sort: query.sort,
    offset: query.offset.max(0),
    page_size: query.page_size.max(1).min(500),
  }
  let filtered : Array[ReviewRow] = []
  let needle = normalized.text.trim().to_lower().to_owned()
  let invalid_range = match (minimum, maximum) {
    (Some(minimum_size), Some(maximum_size)) => minimum_size > maximum_size
    _ => false
  }
  if !invalid_range {
    for row in rows {
      if query_matches(row, normalized, needle) {
        filtered.push(row)
      }
    }
  }
  filtered.sort_by((left, right) => {
    if review_row_precedes(left, right, normalized.sort) {
      -1
    } else if review_row_precedes(right, left, normalized.sort) {
      1
    } else {
      0
    }
  })
  let total = filtered.length()
  let page_size = normalized.page_size
  let start = normalized.offset.min(total)
  let end = (start + page_size).min(total)
  let selected : Array[ReviewRow] = []
  for index = start; index < end; index = index + 1 {
    selected.push(filtered[index])
  }
  {
    rows: selected,
    total_matches: total,
    offset: start,
    page_size,
    page_count: if total == 0 {
      0
    } else {
      (total + page_size - 1) / page_size
    },
    has_previous: start > 0,
    has_next: end < total,
  }
}

///|
/// A lightweight helper for consumers that want to show page numbers.
pub fn review_page_start(page_number : Int32, page_size : Int32) -> Int32 {
  (page_number.max(1) - 1) * page_size.max(1).min(500)
}

///|
/// Report the one-based page containing a row offset.
pub fn review_page_number(offset : Int32, page_size : Int32) -> Int32 {
  offset.max(0) / page_size.max(1).min(500) + 1
}
