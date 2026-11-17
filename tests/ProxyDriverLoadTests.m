#import <Foundation/Foundation.h>
#import <CoreAudio/AudioServerPlugIn.h>
#import <dlfcn.h>
#import <unistd.h>
int main(int argc,char**argv){@autoreleasepool{
 if(argc!=2)return 2;void*handle=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);if(!handle){fprintf(stderr,"%s\n",dlerror());return 1;}
 void*(*factory)(CFAllocatorRef,CFUUIDRef)=dlsym(handle,"ProxyAudio_Create");if(!factory)return 1;
 AudioServerPlugInDriverRef driver=factory(kCFAllocatorDefault,kAudioServerPlugInTypeUUID);
 if(!driver||!(*driver)->Initialize||!(*driver)->StartIO||!(*driver)->DoIOOperation)return 1;
 AudioObjectPropertyAddress bundleAddress={kAudioPlugInPropertyBundleID,kAudioObjectPropertyScopeGlobal,0};
 AudioObjectPropertyAddress devicesAddress={kAudioPlugInPropertyDeviceList,kAudioObjectPropertyScopeGlobal,0};
 if((*driver)->HasProperty(driver,1,getpid(),&bundleAddress)||!(*driver)->HasProperty(driver,1,getpid(),&devicesAddress))return 1;
 CFUUIDRef other=CFUUIDCreate(NULL);BOOL rejects=factory(kCFAllocatorDefault,other)==NULL;CFRelease(other);
 if(!rejects)return 1;puts("PASS: native driver loads, plugin identity requires HAL translation, and unsupported plugin type rejected; no Initialize or audio I/O called");dlclose(handle);return 0;
}}
