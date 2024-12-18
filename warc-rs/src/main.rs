//rust program that reads gzipped warc files.
//1. Iterates over each entry within the file
//2. Extracts the links within the content of each entry
//3. Writes the links to a file
//4. Counts the number of links
//5. Prints the number of links

use clap::{Arg, Command};
use flate2::read::GzDecoder;
use regex::Regex;
use std::fs::File;
use std::io::BufReader;
use std::path::Path;
use warc::WarcReader;

fn main() {
    let matches = Command::new("crawl-works")
        .arg(
            Arg::new("segment")
                .short('s')
                .long("segment")
                .value_name("Segment")
                .help("Sets the input segment file to use"),
        )
        .get_matches();

    let pstr = matches
        .get_one("segment")
        .map(String::as_str)
        .unwrap_or("../data/CC-MAIN-20241015204737-20241015234737-00610.warc.gz");
    //let file = File::open(path).unwrap();
    //let decoder = GzDecoder::new(file);
    //let reader = BufReader::new(decoder);
    //let warc_reader = WarcReader::new(reader);

    let mut links: Vec<String> = Vec::new();
    let re = Regex::new(r#"<a\s+(?:[^>]*?\s+)?href=["']([^"']+)["']"#).unwrap();

    use warc::WarcHeader;
    use warc::WarcReader;

    macro_rules! usage_err {
        ($str:expr) => {
            std::io::Error::new(std::io::ErrorKind::InvalidInput, $str.to_string())
        };
    }

    // let mut file = WarcReader::from_path_gzip(warc_name)?;

    let file = WarcReader::from_path_gzip(pstr);
    let mut file = match file {
        Ok(f) => f,
        Err(e) => {
            eprintln!("Failed to open WARC file: {}", e);
            return;
        }
    };
    let mut stream_iter = file.stream_records();

    let mut count = 0;
    let mut pageCount = 0;

    while let Some(record) = stream_iter.next_item() {
        //extract the content of the record
        let rec = record.unwrap();
        
        let source_url = rec.header(WarcHeader::TargetURI)
            .and_then(|uri| uri.parse::<String>().ok())
            .unwrap_or_else(|| "Unknown".to_string());
        
        pageCount += 1;

        let buf = rec.into_buffered().unwrap();
        let body = buf.body();
        //convert body to string
        let content_result = String::from_utf8_lossy(body);
        //convert content_result into &str and call extract_links
        let content = content_result.as_ref();
        // println!("content: {}", content);
        let links2 = extract_links(content, &re);
        if !links2.is_empty() {
            links.extend(links2);
            count += 1;
        //    if count >= 3 {
        //         break;
        //     };
        }
        //print links
       /*  for link in &links {
            println!("Source URL {} has Links: \n{}", source_url, link);
        } */
    }
    println!("Number of pages and links : {} and {}", pageCount, links.len());
}

fn extract_links(content: &str, re: &Regex) -> Vec<String> {
   
    let links: Vec<String> = re
        .captures_iter(content)
        .map(|cap| cap[1].to_string())
        .collect();
    links
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
