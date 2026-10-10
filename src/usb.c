/* Read-only discovery of USB printer-class devices.
 * The only interface-changing operation remains HP Laser 108a 03f0:e82a.
 * Does not send print bytes, reset devices, or operate other interfaces. */
#include <stdio.h>
#include <string.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>
static int number(io_service_t s, CFStringRef k) {
    int n=0; CFTypeRef p=IORegistryEntryCreateCFProperty(s,k,kCFAllocatorDefault,0);
    if(p && CFGetTypeID(p)==CFNumberGetTypeID()) CFNumberGetValue(p,kCFNumberIntType,&n);
    if(p) CFRelease(p); return n;
}
static CFStringRef string(io_service_t s, CFStringRef k) {
    CFTypeRef p=IORegistryEntryCreateCFProperty(s,k,kCFAllocatorDefault,0);
    if(p && CFGetTypeID(p)==CFStringGetTypeID()) return p;
    if(p) CFRelease(p); return CFRetain(CFSTR(""));
}
static int printer(io_service_t s) {
    if(number(s,CFSTR("bDeviceClass"))==7) return 1;
    io_iterator_t children=0; io_registry_entry_t child; int found=0;
    if(!IORegistryEntryCreateIterator(s,kIOServicePlane,kIORegistryIterateRecursively,&children)) {
        while((child=IOIteratorNext(children))) {
            if(number(child,CFSTR("bInterfaceClass"))==7) found=1;
            IOObjectRelease(child);
        }
        IOObjectRelease(children);
    }
    return found;
}
static void setNumber(CFMutableDictionaryRef row,CFStringRef key,int value) {
    CFNumberRef n=CFNumberCreate(NULL,kCFNumberIntType,&value);
    CFDictionarySetValue(row,key,n); CFRelease(n);
}
static int classic(io_service_t s) {
    IOCFPlugInInterface **p=NULL; IOUSBDeviceInterface197 **d=NULL; SInt32 score=0;
    IOReturn r=IOCreatePlugInInterfaceForService(s,kIOUSBDeviceUserClientTypeID,kIOCFPlugInInterfaceID,&p,&score);
    if(r || !p) return 1;
    (*p)->QueryInterface(p,CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID197),(LPVOID *)&d); (*p)->Release(p);
    if(!d) return 1;
    IOUSBConfigurationDescriptorPtr cfg=NULL; UInt8 active=0;
    int valid=0;
    if(!(*d)->GetConfiguration(d,&active) && active==1 && !(*d)->GetConfigurationDescriptorPtr(d,0,&cfg) && cfg) {
        const unsigned char *b=(const unsigned char *)cfg; unsigned total=b[2]|b[3]<<8; int yes=0;
        for(unsigned i=0;i+2<=total;) {
            unsigned n=b[i],t=b[i+1]; if(n<2 || i+n>total) break;
            if(t==4 && n>=9) yes=b[i+2]==0 && b[i+3]==0 && b[i+5]==7 && b[i+6]==1 && b[i+7]==2;
            if(t==5 && n>=7 && yes && b[i+2]==2 && (b[i+3]&3)==2) { valid=1; break; }
            i+=n;
        }
    }
    if(!valid) { (*d)->Release(d); fprintf(stderr,"Unsupported USB configuration; no settings changed.\n"); return 1; }
    IOUSBFindInterfaceRequest req={kIOUSBFindInterfaceDontCare,kIOUSBFindInterfaceDontCare,kIOUSBFindInterfaceDontCare,kIOUSBFindInterfaceDontCare};
    io_iterator_t it=0; int rc=1;
    if(!(*d)->CreateInterfaceIterator(d,&req,&it)) {
        io_service_t si;
        while((si=IOIteratorNext(it))) {
            IOUSBInterfaceInterface190 **in=NULL; p=NULL;
            r=IOCreatePlugInInterfaceForService(si,kIOUSBInterfaceUserClientTypeID,kIOCFPlugInInterfaceID,&p,&score); IOObjectRelease(si);
            if(r || !p) continue;
            (*p)->QueryInterface(p,CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID190),(LPVOID *)&in); (*p)->Release(p);
            if(!in) continue;
            UInt8 num=255,alt=255;
            if((*in)->GetInterfaceNumber(in,&num) || num!=0) { (*in)->Release(in); continue; }
            r=(*in)->USBInterfaceOpen(in);
            if(r==kIOReturnExclusiveAccess) r=(*in)->USBInterfaceOpenSeize(in);
            if(!r) {
                r=(*in)->GetAlternateSetting(in,&alt);
                if(!r && alt!=0) r=(*in)->SetAlternateInterface(in,0);
                if(!r) r=(*in)->GetAlternateSetting(in,&alt);
                if(!r && alt==0) rc=0;
                (*in)->USBInterfaceClose(in);
            }
            if(rc) fprintf(stderr,"Target USB interface unavailable: 0x%08x; reconnect USB and retry.\n",r);
            (*in)->Release(in); break;
        }
        IOObjectRelease(it);
    }
    (*d)->Release(d); return rc;
}
int main(int argc,char **argv) {
    int change=argc==3 && !strcmp(argv[1],"--classic");
    if(argc!=1 && !change) return 2;
    CFMutableArrayRef devices=CFArrayCreateMutable(NULL,0,&kCFTypeArrayCallBacks);
    io_iterator_t it=0; io_service_t s; int rc=change?1:0;
    if(IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("IOUSBHostDevice"),&it)) return 1;
    while((s=IOIteratorNext(it))) {
        int vid=number(s,CFSTR("idVendor")),pid=number(s,CFSTR("idProduct"));
        int hp=vid==0x03f0 && pid==0xe82a;
        if((change && !hp) || (!change && !hp && !printer(s))) { IOObjectRelease(s); continue; }
        CFStringRef sn=string(s,CFSTR("USB Serial Number")),m=string(s,CFSTR("USB Vendor Name")),p=string(s,CFSTR("USB Product Name"));
        CFMutableDictionaryRef row=CFDictionaryCreateMutable(NULL,0,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
        CFDictionarySetValue(row,CFSTR("serial"),sn); CFDictionarySetValue(row,CFSTR("manufacturer"),m); CFDictionarySetValue(row,CFSTR("product"),p); CFArrayAppendValue(devices,row);
        setNumber(row,CFSTR("vid"),vid); setNumber(row,CFSTR("pid"),pid); setNumber(row,CFSTR("location"),number(s,CFSTR("locationID")));
        if(change && CFEqual(p,CFSTR("HP Laser 108a"))) { char serial[256]={0}; CFStringGetCString(sn,serial,sizeof serial,kCFStringEncodingUTF8); if(!strcmp(serial,argv[2])) rc=classic(s); }
        CFRelease(row); CFRelease(sn); CFRelease(m); CFRelease(p); IOObjectRelease(s);
    }
    IOObjectRelease(it);
    if(!change) {
        CFDataRef data=CFPropertyListCreateData(NULL,devices,kCFPropertyListXMLFormat_v1_0,0,NULL);
        if(!data) rc=1; else { fwrite(CFDataGetBytePtr(data),1,CFDataGetLength(data),stdout); CFRelease(data); }
    }
    CFRelease(devices); return rc;
}
