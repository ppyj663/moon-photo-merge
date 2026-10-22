///|
/// A connected review set of photos joined by at least one qualifying visual
/// fingerprint edge. Members at the ends of a chain need not match directly.
pub(all) struct SimilarityGroup {
  paths : Array[String]
  pair_count : Int32
  minimum_distance : Int32
  maximum_distance : Int32
}

///|
pub(all) struct SimilarityGroupsSummary {
  groups : Int32
  members : Int32
  pairs : Int32
  largest_group : Int32
}

///|
fn add_neighbor(
  adjacency : Map[String, Array[String]],
  path : String,
  neighbor : String,
) -> Unit {
  match adjacency.get(path) {
    Some(neighbors) => neighbors.push(neighbor)
    None => adjacency.set(path, [neighbor])
  }
}

///|
/// Convert qualifying pairs into connected review groups. Group membership
/// is transitive by design and is not a claim that every pair in a group is
/// within the configured distance.
pub fn similarity_groups(
  photos : Array[Photo],
  limit : Int32,
) -> Array[SimilarityGroup] {
  let index = new_similarity_index(limit)
  for photo in photos {
    index.add(photo)
  }
  let pairs = index.all_pairs(limit)
  let adjacency : Map[String, Array[String]] = Map([])
  for pair in pairs {
    add_neighbor(adjacency, pair.0, pair.1)
    add_neighbor(adjacency, pair.1, pair.0)
  }
  let visited : Map[String, Bool] = Map([])
  let group_by_path : Map[String, Int32] = Map([])
  let groups : Array[SimilarityGroup] = []
  for pair in pairs {
    for seed in [pair.0, pair.1] {
      if visited.get(seed) is None {
        let pending = [seed]
        let members : Array[String] = []
        visited.set(seed, true)
        let mut cursor = 0
        while cursor < pending.length() {
          let current = pending[cursor]
          cursor = cursor + 1
          members.push(current)
          match adjacency.get(current) {
            Some(neighbors) =>
              for neighbor in neighbors {
                if visited.get(neighbor) is None {
                  visited.set(neighbor, true)
                  pending.push(neighbor)
                }
              }
            None => ()
          }
        }
        members.sort_by((left, right) => left.lexical_compare(right))
        let group_index = groups.length()
        for photo_path in members {
          group_by_path.set(photo_path, group_index)
        }
        groups.push({
          paths: members,
          pair_count: 0,
          minimum_distance: 177,
          maximum_distance: 0,
        })
      }
    }
  }
  for pair in pairs {
    match group_by_path.get(pair.0) {
      Some(group_index) => {
        let previous = groups[group_index]
        groups[group_index] = {
          paths: previous.paths,
          pair_count: previous.pair_count + 1,
          minimum_distance: previous.minimum_distance.min(pair.2),
          maximum_distance: previous.maximum_distance.max(pair.2),
        }
      }
      None => ()
    }
  }
  groups.sort_by((left, right) => left.paths[0].lexical_compare(right.paths[0]))
  groups
}

///|
/// Summarize connected candidate groups for a report header.
pub fn similarity_groups_summary(
  groups : Array[SimilarityGroup],
) -> SimilarityGroupsSummary {
  let mut members = 0
  let mut pairs = 0
  let mut largest_group = 0
  for group in groups {
    members = members + group.paths.length()
    pairs = pairs + group.pair_count
    largest_group = largest_group.max(group.paths.length())
  }
  { groups: groups.length(), members, pairs, largest_group, }
}

///|
/// Find the connected group containing a path, if it has a qualifying edge.
pub fn find_similarity_group(
  groups : Array[SimilarityGroup],
  path : String,
) -> SimilarityGroup? {
  for group in groups {
    for photo_path in group.paths {
      if photo_path == path {
        return Some(group)
      }
    }
  }
  None
}

///|
/// Export path-sorted connected groups. Consumers should display the rule
/// note because transitive membership does not mean every pair is close.
pub fn similarity_groups_json(groups : Array[SimilarityGroup]) -> String {
  let output = StringBuilder()
  output.write_char('[')
  for group_index = 0
      group_index < groups.length()
      group_index = group_index + 1 {
    if group_index > 0 {
      output.write_char(',')
    }
    let group = groups[group_index]
    output.write_string("{\"paths\":[")
    for path_index = 0
        path_index < group.paths.length()
        path_index = path_index + 1 {
      if path_index > 0 {
        output.write_char(',')
      }
      output.write_string(json_string(group.paths[path_index]))
    }
    output.write_string("],\"pairCount\":")
    output.write_string(group.pair_count.to_string())
    output.write_string(",\"minimumDistance\":")
    output.write_string(group.minimum_distance.to_string())
    output.write_string(",\"maximumDistance\":")
    output.write_string(group.maximum_distance.to_string())
    output.write_char('}')
  }
  output.write_char(']')
  output.to_string()
}

///|
/// Export each candidate photo together with its connected group summary.
pub fn similarity_groups_csv(groups : Array[SimilarityGroup]) -> String {
  let output = StringBuilder()
  output.write_string(
    "group,path,member_count,pair_count,min_distance,max_distance\r\n",
  )
  for group_index = 0
      group_index < groups.length()
      group_index = group_index + 1 {
    let group = groups[group_index]
    for path in group.paths {
      output.write_string((group_index + 1).to_string())
      output.write_char(',')
      output.write_string(csv_field(path))
      output.write_char(',')
      output.write_string(group.paths.length().to_string())
      output.write_char(',')
      output.write_string(group.pair_count.to_string())
      output.write_char(',')
      output.write_string(group.minimum_distance.to_string())
      output.write_char(',')
      output.write_string(group.maximum_distance.to_string())
      output.write_string("\r\n")
    }
  }
  output.to_string()
}

///|
/// Export direct qualifying edges as CSV for use in a spreadsheet.
pub fn similarity_pairs_csv(pairs : Array[(String, String, Int32)]) -> String {
  let output = StringBuilder()
  output.write_string("first_path,second_path,distance_bits\r\n")
  for pair in pairs {
    output.write_string(csv_field(pair.0))
    output.write_char(',')
    output.write_string(csv_field(pair.1))
    output.write_char(',')
    output.write_string(pair.2.to_string())
    output.write_string("\r\n")
  }
  output.to_string()
}
