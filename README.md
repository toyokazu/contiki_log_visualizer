# contiki_log_visualizer
Contiki log visualizer

## Installation

### Install rbenv

Refer the folloing page.
https://dev.classmethod.jp/server-side/language/build-ruby-environment-by-rbenv/


### Install ruby

```
$ rbenv install 2.4.3
$ rbenv global 2.4.3
```

### Install gnuplot

For Linux (Ubuntu, Debian)
```
sudo apt-get install gnuplot
```

For Mac OS X
https://qiita.com/noanoa07/items/a20dccff0902947d3e0c


### Install contiki_log_visualizer and numo-gnuplot

```
$ git clone https://github.com/toyokazu/contiki_log_visualizer.git
$ cd contiki_log_visualizer
$ bundle install
```


## How to use

```
irb
> require './contiki_log_visualizer.rb'
> @mqtt_sn.visualize_node(1)
=> visualize powertrace and radio messages of node 1
> @mqtt_sn.visualize_node(2)
=> visualize powertrace and radio messages of node 2
> @mqtt_sn_dtls.visualize_node(1)
=> visualize powertrace and radio messages of node 1
> @mqtt_sn_dtls.visualize_node(2)
=> visualize powertrace and radio messages of node 1
```
