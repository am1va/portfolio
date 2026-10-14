'use strict';
(()=>{
 const dialog=document.querySelector('#booking-dialog');
 const open=document.querySelector('#open-booking');
 const close=document.querySelector('#close-booking');
 const container=document.querySelector('#calendly-container');
 let initialized=false;
 let bookingUrl;
 try{const url=new URL(window.PORTFOLIO_BOOKING?.url);if(url.protocol==='https:'&&url.hostname==='calendly.com'&&url.pathname.length>1){bookingUrl=url;}}catch{}
 open.addEventListener('click',()=>{
  dialog.showModal();
  if(!bookingUrl||initialized)return;
  initialized=true;
  const fallback=document.querySelector('#calendly-fallback');fallback.href=bookingUrl.href;fallback.hidden=false;
  const status=document.querySelector('#booking-status');status.textContent='Loading available times…';
  const script=document.createElement('script');script.src='https://assets.calendly.com/assets/external/widget.js';script.async=true;
  script.onload=()=>{if(!window.Calendly){status.textContent='The calendar could not load. Use the Calendly link below.';initialized=false;return;}container.replaceChildren();const url=new URL(bookingUrl);url.searchParams.set('hide_event_type_details','1');window.Calendly.initInlineWidget({url:url.href,parentElement:container});const iframe=container.querySelector('iframe');if(iframe)iframe.title='Book a project consultation with Robert';};
  script.onerror=()=>{status.textContent='The calendar could not load. Use the Calendly link below.';initialized=false;};
  document.head.appendChild(script);
 });
 close.addEventListener('click',()=>dialog.close());
 dialog.addEventListener('click',event=>{if(event.target===dialog){const rect=dialog.getBoundingClientRect();if(event.clientX<rect.left||event.clientX>rect.right||event.clientY<rect.top||event.clientY>rect.bottom)dialog.close();}});
 dialog.addEventListener('close',()=>open.focus());
})();