# cordova-plugin-traceroute
Cordova Plugin of Traceroute for iOS


## Features

* Use ICMP protocol (both of send & receive) to communicate with node, more reliable than using UDP protocol
* Domain Name and specific IP address (both of IPv4 & IPv6) are supported

## Thanks to the author of the original Traceroute
https://github.com/L-Zephyr/MyDemos


## Usage

* 1st pararmeter: hostname/IP, it is mandatory
* 2nd pararmeter: max hops, it is optional
```javascript
declare let traceroute: any;

...

traceroute.startTrace('www.google.com', 30,
  (res) => {
    console.log('TraceRoute Success!', res);
  }, (err) => {
    console.log('TraceRoute Failure!', err);
  }
);
```


### Platforms

* Android - Not yet supported
* iOS - Only tested on **XCode 9.2**, you may integrate yourself if you are using different version
