 # Performance 

 Following command can be used to generate some regular testing data:
 
 ```bash
 ruby -e '(0..10).each {|i| puts sprintf("%d,abcdefghijkl,%010d, mnopqrs, %020d, tuvwx, \"...\"\"z\"\"...", i, i, i)}'
 ```