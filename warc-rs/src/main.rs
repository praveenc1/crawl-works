//rust program that reads gzipped warc files.
//1. Iterates over each entry within the file
//2. Extracts the links within the content of each entry
//3. Writes the links to a file
//4. Counts the number of links
//5. Prints the number of links

use clap::{Arg, Command};
use env_logger;
use flate2::bufread::MultiGzDecoder;
use log::{debug, error, info};
use memmap2::Mmap;
use regex::bytes::Regex;
use std::fs::File;
use std::io::{self, BufReader, BufWriter, Read, Write};
use std::path::Path;
use std::time::Instant;
use warc::{WarcHeader, WarcReader};

fn decompress_file(input_path: &str) -> io::Result<String> {
    let output_path = input_path.trim_end_matches(".gz");
    if Path::new(output_path).exists() {
        info!("Using existing decompressed file: {}", output_path);
        return Ok(output_path.to_string());
    }

    info!("Decompressing {} to {}", input_path, output_path);
    let input_file = File::open(input_path)?;
    let decoder = MultiGzDecoder::new(BufReader::new(input_file));
    let mut buffered_writer = BufWriter::new(File::create(output_path)?);

    let bytes_written = io::copy(&mut decoder.take(u64::MAX), &mut buffered_writer)?;
    buffered_writer.flush()?;
    debug!("Decompressed {} bytes to {}", bytes_written, output_path);

    Ok(output_path.to_string())
}

fn main() {
    env_logger::init();

    let start_time = Instant::now();

    let matches = Command::new("crawl-works")
        .arg(
            Arg::new("segment")
                .short('s')
                .long("segment")
                .value_name("Segment")
                .help("Sets the input segment file to use"),
        )
        .arg(
            Arg::new("no-decompress")
                .short('n')
                .long("no-decompress")
                .help("Bypasses decompression of the input file"),
        )
        .get_matches();

    let pstr = matches
        .get_one("segment")
        .map(String::as_str)
        .unwrap_or("../data/CC-MAIN-20241015204737-20241015234737-00610.warc.gz");

    info!("Using segment file: {}", pstr);

    let mut uncompressed_path = pstr.to_string();

    // Decompress file first
    let bypass_decompression = matches.contains_id("no-decompress");
    if !bypass_decompression {
        match decompress_file(pstr) {
            Ok(path) => uncompressed_path = path,
            Err(e) => {
                error!("Failed to decompress file: {}", e);
                return;
            }
        };
    }

    // Now use memory mapping on uncompressed file
    let file = File::open(&uncompressed_path).expect("Failed to open uncompressed file");
    let mmap = unsafe { Mmap::map(&file).expect("Failed to create memory map") };
    let warc_reader = WarcReader::new(&mmap[..]);

    let re = Regex::new(r#"<a\s+(?:[^>]*?\s+)?href\s*=\s*["']\s*([^"'\s]+)\s*["']"#).unwrap();
    //let re = Regex::new(br#"<a\s+(?:[^>]*?\s+)?href=["']([^"'\s]+)["']"#).unwrap();
    let mut links: Vec<String> = Vec::new();
    let mut page_count = 0;

    for record in warc_reader.iter_records() {
        page_count += 1;
        match record {
            Ok(record) => {
                let source_url = record
                    .header(WarcHeader::TargetURI)
                    .and_then(|uri| uri.parse::<String>().ok())
                    .unwrap_or_else(|| "Unknown".to_string());

                let content = record.body();
                if !content.is_empty() {
                    let page_links = extract_links(content, &re);
                    if !page_links.is_empty() {
                        for link in page_links {
                            debug!("Source URL {} has Link: {}", source_url, link);
                            links.push(link);
                        }
                    } else {
                        debug!("No links found for URL: {}", source_url);
                    }
                } else {
                    debug!("Empty content for URL: {}", source_url);
                }
                // if let Ok(content) = record.body() {
                //     if !content.is_empty() {
                //         let page_links = extract_links(content, &re);
                //         if !page_links.is_empty() {
                //             for link in page_links {
                //                 debug!("Source URL {} has Link: {}", source_url, link);
                //                 links.push(link);
                //             }
                //         } else {
                //             debug!("Empty content for URL: {}", source_url);
                //         }
                //     } else {
                //         debug!("Empty content for URL: {}", source_url);
                //     }
                // } else {
                //     error!(
                //         "Failed to convert record body to UTF-8 for URL: {}",
                //         source_url
                //     );
                // }
            }
            Err(e) => {
                error!("Error reading record: {}", e);
            }
        }
    }

    let elapsed_time = start_time.elapsed();
    info!(
        "Number of pages and links: {} and {}",
        page_count,
        links.len()
    );

    info!("Total execution time: {:?}", elapsed_time);
}

fn extract_links(content: &[u8], re: &Regex) -> Vec<String> {
    /*
    let links: Vec<String> = re
        .captures_iter(content)
        .map(|cap| cap[1].to_string())
        .collect();
    links
    */

    re.find_iter(content)
        .filter_map(|mat| {
            // Convert the matched bytes to a String if valid UTF-8
            std::str::from_utf8(mat.as_bytes())
                .ok()
                .map(|s| s.to_string())
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_extract_links() {
        let html = r#"<a href="http://example.com">Link</a>
                     <a href="https://test.com">Another</a>
                     <div href="invalid">Not a link</div>"#;

        let re = Regex::new(r#"<a\s+(?:[^>]*?\s+)?href=["']([^"']+)["']"#).unwrap();
        let links = extract_links(html, &re);

        assert_eq!(links.len(), 2);
        assert_eq!(links[0], "http://example.com");
        assert_eq!(links[1], "https://test.com");
    }
}
