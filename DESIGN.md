# Design Principles
 1. Optimize for running 3B records and reduced cloud costs
 2. Use Medallion Architecture


 # Pipeline

Report and visualize metrics:
1. Number of records processed per sec
2. Show current layer being processed
3. No. of workers
4. Time elapsed
5. No. of cores, memory, network, and storage in use
6. 

 ## Bronze

 Steps:
 1. Load cc_index into  DuckDB
 2. Sample the full db into Mini (15% sampling), Micro (.1% sampling), and Nano (0.2% of Micro)DBs

 ## Silver

 Steps

 1. Extract links from each page
 2. Write host_name, source_page, link, language to a .csv file
 3. Import the .csv into a Kuzu DB

 ## Gold

 Steps

 1. Query Kuzu DB and visualize the links
 2. Allow filtering by language